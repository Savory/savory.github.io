---
published: true
title: "Talking to other services : RabbitMQ in Danet"
excerpt: "Last time we ended on a promise : the day a second service, quite possibly not written in TypeScript, needs to consume your messages, you want a real broker. Today we plug one in."
---

![danet-logo.svg]({{site.baseurl}}/assets/images/danet-logo.svg)

Welcome ! When we covered [cron jobs and queues]({{site.baseurl}}{% post_url 2025-07-18-background-jobs-in-danet %}), we ended on a promise : a Deno KV queue is durable, but it is not a broker, and the day a second service needs the same messages you want a real one. Today we keep that promise.

## Three ways to send a message, and how to pick

Danet now gives you three. They look alike, they are not interchangeable, and the question that separates them is always the same : how far does the message have to travel ?

- **Events**, with `EventEmitter` and `@OnEvent`, travel across your own code. In process, in memory, gone when the process is. Perfect for decoupling a module from another module.

- **KV Queue**, with `KvQueue` and `@OnQueueMessage`, travel across time. Backed by `Deno.kv`, so a message survives a restart, and no infrastructure to run. Still one Deno application, though.

- **RabbitMQ**, with `RabbitMQ` and `@OnRabbitMQMessage`, travel across services. A broker sits between your applications, holds the queues, routes the messages, and does not care what language wrote them.

Pick the smallest one that reaches. Events until the message leaves the process, KV Queue until it leaves the app, RabbitMQ after that.

## Installing

RabbitMQ is not in the core package, it is its own :

```sh
deno add jsr:@danet/rabbitmq
```

You need `@danet/core` 2.11.0 or later, and a broker. For local work, one container is enough :

```sh
docker run -d -p 5672:5672 -p 15672:15672 rabbitmq:3-management
```

One thing worth knowing before you lose an afternoon to it : against a 4.x broker that connection fails with a bare `read ECONNRESET`, because the AMQP client we build on still asks for a 4096 byte frame and 4.x refuses anything under 8192. Append `?frameMax=8192` to the URL and it connects.

Then import `RabbitMQModule.forRoot()` in your root module with a connection string :

```ts src/app.module.ts
import { Module } from 'jsr:@danet/core';
import { RabbitMQModule } from 'jsr:@danet/rabbitmq';
import { OrderService } from './order/service.ts';
import { OrderConsumer } from './order/consumer.ts';

@Module({
  imports: [
    RabbitMQModule.forRoot({
      url: 'amqp://guest:guest@localhost:5672',
      prefetch: 10,
    }),
  ],
  injectables: [OrderService, OrderConsumer],
})
export class AppModule {}
```

`prefetch` is optional, and we come back to it further down.

## Publishing

Inject `RabbitMQ` like any other service and call `sendMessage` with a queue name and a payload :

```ts src/order/service.ts
import { Injectable } from 'jsr:@danet/core';
import { RabbitMQ } from 'jsr:@danet/rabbitmq';
import { OrderRepository } from './repository.ts';
import { Order } from './class.ts';

@Injectable()
export class OrderService {
  constructor(
    private repository: OrderRepository,
    private rabbit: RabbitMQ,
  ) {}

  async create(order: Order) {
    const saved = await this.repository.insert(order);
    await this.rabbit.sendMessage('order.created', { orderId: saved.id });
    return saved;
  }
}
```

The queue is declared durable on the way out, so it exists whether or not anybody is listening yet. The payload is JSON encoded and marked persistent. The returned boolean is `false` when the broker is pushing back and the write buffer is full, which is your cue to slow down rather than an error.

## Consuming

Decorate a method with the queue it handles :

```ts src/order/consumer.ts
import { Injectable, Logger } from 'jsr:@danet/core';
import { OnRabbitMQMessage } from 'jsr:@danet/rabbitmq';
import { InvoiceService } from '../invoice/service.ts';

@Injectable()
export class OrderConsumer {
  private logger = new Logger('OrderConsumer');

  constructor(private invoiceService: InvoiceService) {}

  @OnRabbitMQMessage('order.created')
  async onOrderCreated(payload: { orderId: string }) {
    await this.invoiceService.generate(payload.orderId);
    this.logger.log(`invoice ready for ${payload.orderId}`);
  }
}
```

The class goes in `injectables`. At bootstrap we walk the injectables and read the metadata off their methods. Controllers are not scanned.

## Fanning out

> But Thomas, I have three services that all want to know an order shipped !

That is what exchanges are for. Instead of publishing to a queue, you publish to an exchange with a routing key, and every queue bound to that key gets a copy :

```ts
await this.rabbit.publish('orders', 'order.shipped', { orderId }, 'topic');
```

On the other side, pass binding options as the second argument of the decorator. The queue is declared, the exchange is declared, the two are bound :

```ts src/notification/consumer.ts
@Injectable()
export class NotificationConsumer {
  @OnRabbitMQMessage('order.shipped.email', {
    exchange: 'orders',
    exchangeType: 'topic',
    routingKey: 'order.shipped',
  })
  sendShippingEmail(payload: { orderId: string }) {
    // ...
  }
}
```

A second service binding `order.shipped.analytics` to the same exchange gets its own copy of every message, and a `routingKey` of `order.*` gets it a copy of every order event at once. The decorator itself has no wildcards, but the broker does, and that is the right place for them.

## Acknowledgements, and losing nothing

Messages are acknowledged for you, on the only rule that makes sense : your handler resolves, the message is acked and gone. Your handler throws, the message is nacked **without requeue**, so it goes to whatever dead letter policy you configured instead of coming straight back and looping forever.

That is deliberately not the KV queue's behaviour, where a failing message is retried a few times and then dropped. Here a failure is a thing you can go and look at.

`prefetch` is how you share the work. It caps how many unacknowledged messages the broker will hand a single consumer, so two instances of the same service consuming the same queue take turns instead of one of them swallowing the backlog. Six messages, two instances, three each.

## What it does not do yet

The package is young, so let us be straight about it. One handler per queue inside a given app. No DTO validation : payloads are parsed as they arrive, the `@Body` validation you get on routes does not apply here, so validate inside the handler if the sender is not you. And no wildcard matching in the decorator, on purpose, because a topic exchange already does it better.

Well, that's it folks ! It wasn't hard, now you know !

Documentation : [https://danet.land](https://danet.land)

Repository : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
