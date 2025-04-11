---
published: true
title: WebSockets in Danet
excerpt: Same controllers, same dependency injection, same guards, same port. Only the transport changes.
---

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)

Welcome ! Every article we wrote so far was about building a REST API. Danet does more than that, and today we open a WebSocket.

The good news is that there is almost nothing new to learn. A WebSocket controller is a class with a decorator, it gets its dependencies injected the same way, and your guards, middlewares and exception filters work on it unchanged. We also do not pull in a third party library for this, we use the standard [WebSocket API](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API).

## Your first controller

```ts src/events/controller.ts
import { Body, OnWebSocketMessage, WebSocketController } from 'jsr:@danet/core';

@WebSocketController('ws')
export class EventsController {
  @OnWebSocketMessage('events')
  handleEvent(@Body() data: unknown) {
    return { topic: 'events', data };
  }
}
```

Register it in a module exactly like an HTTP controller, in the `controllers` array. There is no separate registration, no second server, no extra port : your controller listens on the same port as the HTTP server, at `ws://localhost:3000/ws`.

## Everything is a topic

Danet expects every message to be an object with a `topic` and a `data` property. From the browser :

```ts
const websocket = new WebSocket('ws://localhost:3000/ws');

websocket.onopen = () => {
  websocket.send(
    JSON.stringify({ topic: 'events', data: { obiwan: 'kenobi' } }),
  );
};
```

The `topic` picks the handler, `data` is what your handler receives. Your handlers return the same shape, and that is what gets sent back.

This is the one convention you have to accept. In exchange, you get routing.

## Topics are routes

Under the hood we run Hono's smart router on the topic, the very same router that handles your HTTP paths. So a topic is not a flat string you compare, it is a pattern :

```ts src/events/controller.ts
@OnWebSocketMessage('user/:userId')
handleUser(@Param('userId') userId: string) {
  return { topic: 'hello', data: userId };
}
```

`@Param()` works exactly as it does on an HTTP route. And since it is the same router, the fancy patterns come for free :

- `posts/:id/comment/:comment_id`
- `animal/:type?` for an optional segment
- `post/:date{[0-9]+}/:title{[a-z]+}` to constrain with a regex

That last one is worth a second look. You can reject malformed topics at the routing layer instead of writing validation inside your handler.

## Reading the message

`@Body()` behaves like it does over HTTP. Take the whole payload, or pluck a property out of it :

```ts
@OnWebSocketMessage('events')
handleEvent(@Body('name') name: string) {
  return { topic: 'hello', data: name };
}
```

And when you need the socket itself, there is `@WebSocket()` :

```ts
import { WebSocket, WebSocketInstance } from 'jsr:@danet/core';

@OnWebSocketMessage('events')
handleEvent(@WebSocket() socket: WebSocketInstance) {
  socket.send(JSON.stringify({ topic: 'hello', data: 'there' }));
}
```

Few key points :

- `WebSocketInstance` is a plain `WebSocket` plus an `id`. That id is stable for the life of the connection, which is what you want the moment you start keeping a map of connected clients, building rooms, or broadcasting to everyone but the sender.

- Returning a value sends it back to the caller. Calling `socket.send()` yourself is for everything else, like pushing to a socket that did not ask.

## Guards, middlewares, filters

There is no WebSocket-flavoured version of these. They are the same classes.

```ts
@UseGuard(JwtAuthGuard)
@OnWebSocketMessage('events')
handleEvent(@Body() data: unknown) {
  return { topic: 'events', data };
}
```

Inside a guard or a middleware, `ExecutionContext` gains two properties when it is handling a socket message : `context.websocket`, the current socket, and `context.websocketTopic`, the topic being handled. A guard can therefore make a decision based on which topic was asked for, which is the WebSocket equivalent of routing on a path.

One real difference, and it is about errors. Over HTTP you throw an `HttpException` and the exception layer turns it into a status code. There are no status codes here, so you return a message instead :

```ts
return { topic: 'error', data: { customMessage: 'not cool my friend' } };
```

Well, that's it folks ! It wasn't hard, now you know !

If you only need to push updates from the server to the browser and never the other way around, a WebSocket is more machinery than you need. We will talk about Server-Sent Events another day.

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

And the GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
