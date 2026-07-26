---
published: true
title: Pushing updates with Server-Sent Events
excerpt: A WebSocket is a phone call. Sometimes all you need is a newsletter. Danet does Server-Sent Events with one decorator.
---

![danet-logo.svg]({{site.baseurl}}/assets/images/danet-logo.svg)

Welcome ! Last time we [opened a WebSocket]({{site.baseurl}}{% post_url 2025-04-11-websockets-in-danet %}), and we closed that article by saying that if the browser never talks back, a WebSocket is more machinery than you need. Today we keep that promise : Server-Sent Events.

## SSE or WebSocket ?

The question answers itself once you ask who speaks.

A WebSocket is a phone call. Both sides talk, whenever they want, over a connection that stopped being HTTP right after the handshake.

[Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) are a newsletter. The client subscribes once, the server sends text down the pipe, and that is the entire relationship. It stays plain HTTP the whole way through, which means your proxies, your load balancer and your `Authorization`-shaped worries all behave exactly as they do everywhere else in your API.

Notifications, a progress bar, a live dashboard, log tailing : all newsletters. Reach for SSE first, and upgrade to a WebSocket the day you actually need the client to answer.

## One decorator

```ts src/notification/controller.ts
import { Controller, Param, SSE } from 'jsr:@danet/core';
import { NotificationService } from './service.ts';

@Controller('notification')
export class NotificationController {
  constructor(private notificationService: NotificationService) {}

  @SSE(':userId')
  streamFor(@Param('userId') userId: string): EventTarget {
    return this.notificationService.streamFor(userId);
  }
}
```

That is an ordinary controller. Register it in the `controllers` array of your module like any other, and `GET /notification/42` becomes a stream.

The one rule is the return type : **an `@SSE()` handler must return an `EventTarget`**. Not a promise of data, not an object we serialise. You hand us the thing that will emit, we subscribe to it and keep the connection open.

## Emitting

`EventTarget` is a web standard, so your service is just standard JavaScript plus one Danet class :

```ts src/notification/service.ts
import { Injectable, SSEEvent } from 'jsr:@danet/core';

@Injectable()
export class NotificationService {
  private streams = new Map<string, EventTarget>();

  streamFor(userId: string): EventTarget {
    let stream = this.streams.get(userId);
    if (!stream) {
      stream = new EventTarget();
      this.streams.set(userId, stream);
    }
    return stream;
  }

  notify(userId: string, message: string) {
    this.streams.get(userId)?.dispatchEvent(
      new SSEEvent({
        id: crypto.randomUUID(),
        event: 'notification',
        data: { message },
      }),
    );
  }

  end(userId: string) {
    this.streams.get(userId)?.dispatchEvent(
      new SSEEvent({ event: 'close', data: 'bye' }),
    );
    this.streams.delete(userId);
  }
}
```

Inject that service anywhere (a controller, another service, a cron job) and calling `notify()` pushes a line to a browser that is sitting on the other end of an open connection.

Few key points :

- `SSEEvent` is the class you instantiate. `SSEMessage` is the *interface* describing what you pass to it : `data` is required, `event`, `id` and `retry` are optional. The two names are easy to mix up, and the documentation used to mix them up too.

- `data` can be an object. We `JSON.stringify` it for you before it goes on the wire, because the SSE format only carries text.

- **An event named `close` ends the stream.** That string is not a convention we suggest, it is the signal we look for : dispatch it and we stop the loop and close the connection. Send one when you are done, otherwise that connection stays open forever.

- **Do not dispatch before you return.** We attach our listener to your `EventTarget` after your handler has returned it, so anything you fire synchronously inside the handler goes nowhere. If you owe a new subscriber an immediate first message, send it from a `setTimeout` or an `await`ed tick, not inline.

- `@SSE()` registers a `GET` route. There is no other option, and `EventSource` would not use one anyway.

## The client

Nothing to install. `EventSource` has been in browsers for years :

```js public/app.js
const events = new EventSource('/notification/42');

events.addEventListener('notification', ({ data }) => {
  console.log(JSON.parse(data).message);
});

events.addEventListener('close', () => events.close());
```

The `event` field you passed to `SSEEvent` is the event name you listen for here. Leave it out and the browser fires a generic `message` event instead. And if the connection drops, `EventSource` reconnects on its own. That is what the `retry` field is for, in milliseconds, telling it how long to wait first.

## Guards, params, everything else

An SSE route goes through the same pipeline as the rest of your controllers. Middlewares run, guards run before your handler is called, `@Param()` and `@Query()` resolve normally, and dependency injection is unchanged. There is no SSE-flavoured version of anything.

There is one honest catch, and it is the browser's fault rather than ours : `EventSource` cannot set request headers. If you protected your API with a [global JWT guard]({{site.baseurl}}{% post_url 2024-09-27-jwt-auth-in-danet %}), no `Authorization: Bearer` header is going to reach it from an `EventSource`. Your options are a cookie, with `new EventSource(url, { withCredentials: true })`, or a short-lived token in the query string. A cookie is the better one.

Well, that's it folks ! It wasn't hard, now you know !

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

And the GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
