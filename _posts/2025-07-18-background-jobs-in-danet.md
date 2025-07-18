---
published: true
title: Cron jobs and queues in Danet
excerpt: "Every API eventually needs two more things : something that runs at 3am, and something that runs later. Deno ships both natively, Danet puts a decorator on them."
---

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)

Welcome ! Your API answers requests. Then one day it also has to send the nightly report, and to resize a picture nobody wants to wait for. Today we do both, without adding a single piece of infrastructure.

## Two questions, two tools

`Deno.cron` answers "this must happen at 3am". A time comes, code runs, nobody asked for it.

A Deno KV queue answers "this must happen, but not while somebody is waiting". A request arrives, you accept it, you hand the work off and you reply immediately.

They look alike because both run code outside a request. They are not interchangeable : one is triggered by a clock, the other by you.

## Turning the runtime on

Both APIs are still unstable in Deno, so both need to be enabled. Put them in your `deno.json` once and stop thinking about it :

```json deno.json
{
  "unstable": ["cron", "kv"],
  "tasks": {
    "start": "deno run --allow-net --allow-env --allow-read run.ts"
  }
}
```

On the command line the same two flags are `--unstable-cron` and `--unstable-kv`.

## Cron

`ScheduleModule` goes in `imports`, and the class holding your jobs goes in `injectables` :

```ts src/app.module.ts
import { Module, ScheduleModule } from 'jsr:@danet/core';
import { MaintenanceTasks } from './maintenance/tasks.ts';

@Module({
  imports: [ScheduleModule],
  injectables: [MaintenanceTasks],
})
export class AppModule {}
```

```ts src/maintenance/tasks.ts
import { Cron, Injectable, Interval, Logger, Timeout } from 'jsr:@danet/core';
import { SessionService } from '../session/service.ts';

@Injectable()
export class MaintenanceTasks {
  private logger = new Logger('MaintenanceTasks');

  constructor(private sessionService: SessionService) {}

  @Cron('0 3 * * *')
  async deleteExpiredSessions() {
    const deleted = await this.sessionService.deleteExpired();
    this.logger.log(`deleted ${deleted} expired sessions`);
  }

  @Interval(30_000)
  refreshStats() {
    this.logger.log('refreshing stats');
  }

  @Timeout(5_000)
  warmUpCache() {
    this.logger.log('cache warmed up');
  }
}
```

Few key points :

- The class lives in `injectables`. At bootstrap we walk the injectables and read the metadata off their methods. Controllers are not scanned, and a method that is not a route has nothing to do on a controller anyway.

- Injection works, and `this` is your instance. A scheduled method is an ordinary method on an ordinary service, so `this.sessionService` is right there. Anything you can inject in a controller you can inject here, including the notification service we wrote for [Server-Sent Events]({{site.baseurl}}{% post_url 2025-05-30-real-time-with-sse %}) : a cron job that pushes to open browser connections is about six lines.

- `@Interval` and `@Timeout` are `setInterval` and `setTimeout`, in milliseconds, counted from application start. Those two are plain timers, so they need no flag, and we clear them for you when the app closes.

- **Five fields, and only five.** Deno's parser has no seconds field, its day of week runs from 1 to 7 (Sunday is `7`, never `0`), and its months run from 1 to 12. `CronExpression` is a convenience enum we inherited from Nest, where expressions have six fields, and about a third of it is not a convenience at all : `EVERY_WEEK`, `EVERY_WEEKEND`, `EVERY_YEAR` and every single `MONDAY_TO_FRIDAY_*` are rejected with `Invalid cron schedule` the moment your app boots. `EVERY_30_MINUTES` and the hourly ones are fine. Writing the five field string yourself is safer.

- The name of the job is the name of the method, and `Deno.cron` wants those names unique. Two services with a `cleanUp()` method each, and the second one fails to register.

- A timer is not a cron. `@Interval` lives and dies with the process, while `Deno.cron` is a runtime feature that Deno Deploy takes over and schedules for you. Anything that really must happen once a day belongs in `@Cron`.

## The queue

> But Thomas, my job is triggered by a user, and it takes four minutes !

Different problem. When the work is caused by a request but has no business being done inside it, you want a queue.

`KvQueueModule.forRoot()` takes the path you would have handed to `Deno.openKv`, and nothing else :

```ts src/app.module.ts
import { KvQueueModule, Module } from 'jsr:@danet/core';
import { PictureController } from './picture/controller.ts';
import { ThumbnailConsumer } from './picture/consumer.ts';

@Module({
  imports: [KvQueueModule.forRoot('./data/queue.db')],
  controllers: [PictureController],
  injectables: [ThumbnailConsumer],
})
export class AppModule {}
```

To produce, inject `KvQueue` and send a type plus a payload :

```ts src/picture/controller.ts
import { Body, Controller, KvQueue, Post } from 'jsr:@danet/core';
import { PictureDto } from './dto.ts';
import { PictureService } from './service.ts';

@Controller('picture')
export class PictureController {
  constructor(
    private pictureService: PictureService,
    private queue: KvQueue,
  ) {}

  @Post()
  async upload(@Body() picture: PictureDto) {
    const id = await this.pictureService.save(picture);
    await this.queue.sendMessage('thumbnail.requested', { pictureId: id });
    return { id, status: 'processing' };
  }
}
```

To consume, decorate a method with the type it handles :

```ts src/picture/consumer.ts
import { Injectable, Logger, OnQueueMessage } from 'jsr:@danet/core';
import { generateThumbnail } from './thumbnail.ts';

const logger = new Logger('ThumbnailConsumer');

@Injectable()
export class ThumbnailConsumer {
  @OnQueueMessage('thumbnail.requested')
  async onThumbnailRequested(payload: { pictureId: string }) {
    await generateThumbnail(payload.pictureId);
    logger.log(`thumbnail ready for ${payload.pictureId}`);
  }
}
```

Few key points :

- **A consumer runs detached from its instance.** Notice that the logger sits outside the class. We hand your method to `Deno.Kv.listenQueue` as a plain function, so `this` inside it is not your service, and reaching for `this.anything` throws. Import the function that does the work, like `generateThumbnail` above, and keep the consumer itself dumb.

- One type, one handler, and no wildcards. A message arriving with a type nobody claimed throws `Unhandled message type`.

- On the wire a message is `{ type, data }`. That matters the day something that is not a Danet application writes to the same store : build that envelope yourself, or nothing will match.

- The queue is durable. Messages live in Deno KV, so they survive a restart, and a consumer that throws gets the message handed to it again a few times, with a growing delay, before Deno gives up. A failed job is not lost silently, but it is not retried forever either.

## When this stops being enough

A KV queue is durable and it is shared by every instance talking to the same store, which is more than most people expect from something you get for free.

What it is not is a broker. The day a second service, quite possibly written in something other than TypeScript, needs to consume the same messages, you want a real one sitting between the two. That is another article.

Until then, the runtime you already have does the job.

Well, that's it folks ! It wasn't hard, now you know !

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

And the GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
