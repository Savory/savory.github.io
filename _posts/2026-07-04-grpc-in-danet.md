---
published: true
title: "gRPC controllers in Danet"
excerpt: "A new package turns a Danet controller into a real gRPC service : same injector, same guards, same exception filters, its own port."
---

![danet-logo.svg]({{site.baseurl}}/assets/images/danet-logo.svg)

Welcome ! Today we serve a Danet controller over gRPC, without giving up anything you already use.

`@danet/grpc` is a new package, and it starts a real gRPC server : HTTP/2, Protobuf, its own port.
Two requirements before anything else. Deno **2.8** or later, because server side gRPC needs `node:http2` trailer support, and `@danet/core` **2.11.0** or above.

```bash
deno add jsr:@danet/core jsr:@danet/grpc
```

## The contract

gRPC starts with the schema, not with the code.

```proto src/todo/todo.proto
syntax = "proto3";

package todo;

service TodoService {
  rpc GetTodo (GetTodoRequest) returns (Todo) {}
  rpc CreateTodo (CreateTodoRequest) returns (Todo) {}
}

message GetTodoRequest {
  string id = 1;
}

message CreateTodoRequest {
  string title = 1;
}

message Todo {
  string id = 1;
  string title = 2;
  bool done = 3;
}
```

## The controller

```ts src/todo/grpc.controller.ts
import {
  GrpcController,
  GrpcMetadata,
  GrpcMethod,
  GrpcPayload,
  loadProto,
} from '@danet/grpc';
import { UseGuard } from '@danet/core';
import { TodoService } from './todo.service.ts';
import { ApiKeyGuard } from '../auth/api-key.guard.ts';

const proto = loadProto(new URL('./todo.proto', import.meta.url).pathname);

@GrpcController(proto.todo.TodoService.service)
export class TodoGrpcController {
  constructor(private todoService: TodoService) {}

  @GrpcMethod()
  GetTodo(@GrpcPayload() request: { id: string }) {
    return this.todoService.getById(request.id);
  }

  @UseGuard(ApiKeyGuard)
  @GrpcMethod()
  CreateTodo(
    @GrpcPayload() request: { title: string },
    @GrpcMetadata('x-api-key') apiKey: string[],
  ) {
    return this.todoService.create(request.title);
  }
}
```

Few key points :

- `@GrpcController` takes a **service definition**, not a route string. `loadProto` parses the `.proto` at runtime and gives back the package tree, so `proto.todo.TodoService.service` is the service you just declared. No codegen step, no build step.

- That path is resolved by the process, not by the module, so `'./todo.proto'` only works while your working directory happens to be the right one. Anchor it on `import.meta.url` and stop thinking about it.

- `@GrpcMethod()` binds to the RPC of the same name. Pass one explicitly, `@GrpcMethod('GetTodo')`, when your method is named differently. An RPC that no method claims answers `UNIMPLEMENTED` by itself.

- `@GrpcPayload()` is the decoded request message. `@GrpcMetadata('x-api-key')` is the gRPC equivalent of a header, and it hands you an **array**, because a metadata key is allowed to repeat. Drop the key to receive the whole `Metadata` object.

- The class goes into the `controllers` array of a module like any other controller, and constructor injection works as usual. `TodoService` here is the very same singleton your HTTP controllers inject.

## Two servers, one application

```ts run.ts
import { DanetApplication } from '@danet/core';
import { GrpcServer } from '@danet/grpc';
import { AppModule } from './src/app.module.ts';

const app = new DanetApplication();
const grpc = new GrpcServer(app);

await app.init(AppModule);

await grpc.listen(50051);
await app.listen(3000);
```

Build the `GrpcServer` **before** `app.init()`. Constructing it registers a transport, and bootstrap then hands it every controller carrying gRPC metadata. Build it after, and those controllers go to the HTTP router instead, which has no path to register them under and brings the whole app down at boot with a `TypeError`.

`listen` resolves with the port it actually bound, so pass `0` in your tests and let the OS pick. Its second argument takes a `grpc.ServerCredentials`, and without one the server binds insecure ; a plain server certificate through `createSsl` already works, even though the package still lists TLS as planned.

Both servers run off one application, one injector, one set of services. Your REST API keeps answering on 3000 while gRPC answers on 50051.

## The rest is just Danet

> But Thomas, what about my guards ?

They run. Middleware runs, guards run, parameters resolve, request scoped injectables are rebuilt for every call, exception filters catch what you throw. The gRPC router reuses the exact same executors the HTTP router uses.

Which is also the one thing that will bite you. If you followed [the JWT article]({{site.baseurl}}{% post_url 2024-09-27-jwt-auth-in-danet %}), your authentication guard is registered as `GLOBAL_GUARD`, and a global guard is global : it runs on gRPC calls too, where `context.req` does not exist. Reading a header there gets you `UNKNOWN: Cannot read properties of undefined`.

So teach the guard about both transports.

```ts src/auth/jwt-auth.guard.ts
// still inside JwtAuthGuard
private getToken(context: ExecutionContext): string | undefined {
  return context.grpcMetadata
    ? context.grpcMetadata.get('authorization')[0]
    : context.req.header('authorization');
}
```

`@Public()` keeps working, `context.getHandler()` is set for gRPC calls as well. Middleware reading `context.req` or `context.res` has the same problem and no equivalent fix, so leave that middleware to your HTTP controllers.

## Errors

Throw the way you already throw. An `HttpException` is mapped to the closest gRPC status : 404 to `NOT_FOUND`, 403 to `PERMISSION_DENIED`, 429 to `RESOURCE_EXHAUSTED`, 400 to `INVALID_ARGUMENT`. Anything that is not an `HttpException` becomes `UNKNOWN`. A guard returning `false` throws `ForbiddenException`, so a denied call reaches the client as `PERMISSION_DENIED`.

The built in exceptions take no argument though, so `new NotFoundException()` sends the client the words `Not found` and nothing more. Reach for `new HttpException(404, 'no todo with that id')` when the caller deserves to read something useful.

## What is not there yet

This is a first release, sorry for the following missing pieces.

- **Unary RPCs only.** A streaming RPC is skipped at bootstrap with a warning in your logs, and the client calling it receives `UNIMPLEMENTED`, which is at least honest. Streaming is planned.

- **No validation on the payload.** The Protobuf schema is the contract, so the decorators from [the body validation article]({{site.baseurl}}{% post_url 2024-05-03-body-validation-in-danet-v2 %}) do not apply to `@GrpcPayload`.

- **No HTTP shaped middleware**, as above.

- Static Protobuf codegen is planned too, for people who would rather have typed messages than `{ id: string }`.

Well, that's it folks ! It wasn't hard, now you know !

Documentation : [https://danet.land](https://danet.land)

Repository : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
