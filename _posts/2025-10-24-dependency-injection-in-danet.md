---
published: true
title: "Getting the most out of Danet's injector"
excerpt: "Every article on this blog has done the same thing without explaining it : put a class in injectables, ask for it in a constructor, get an instance. Today we open that box."
---

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)

Welcome ! Every article on this blog has done the same thing without ever explaining it : put a class in `injectables`, ask for it in a constructor, get an instance back. Today we open that box.

## The short form is a short form

When you write this :

```ts src/app.module.ts
import { Module } from 'jsr:@danet/core';
import { TodoController } from './todo/todo.controller.ts';
import { TodoService } from './todo/todo.service.ts';

@Module({
  controllers: [TodoController],
  injectables: [TodoService],
})
export class AppModule {}
```

you are registering a pair. The token is `TodoService`, the thing to build is `TodoService`. A class is its own token, which is why constructor injection needs no annotation : the parameter type *is* the lookup key.

The long form spells the pair out :

```ts src/app.module.ts
injectables: [
  { token: 'TODO_SERVICE', useClass: TodoService },
]
```

`useClass` is what you reach for when the token and the implementation are not the same thing. We already used it to register a guard under `GLOBAL_GUARD` in [the JWT article]({{site.baseurl}}{% post_url 2024-09-27-jwt-auth-in-danet %}) : the framework asks for a token it defines, you decide which class answers.

If you have seen `new TokenInjector(TodoService, 'TODO_SERVICE')` in older code or in the generated starter, it does the same job. It still works, it is only deprecated. The plain object is the one to write today.

## Injecting something that is not a class

The other half of the long form is `useValue`, and it takes anything : a configuration object, a client you built by hand, a mock in a test.

A value has no class to be its own token, so you name it yourself. Keep the name and the type in their own file, so nothing has to import a module to inject its options :

```ts src/config/constant.ts
export const CONFIG_OPTIONS = 'CONFIG_OPTIONS';

export interface ConfigOptions {
  folder: string;
  cacheTtl: number;
}
```

```ts src/config/config.service.ts
import { Inject, Injectable } from 'jsr:@danet/core';
import { CONFIG_OPTIONS } from './constant.ts';
import type { ConfigOptions } from './constant.ts';

@Injectable()
export class ConfigService {
  constructor(@Inject(CONFIG_OPTIONS) private options: ConfigOptions) {}

  get folder(): string {
    return this.options.folder;
  }
}
```

Few key points :

- `@Inject()` takes precedence over the parameter type. Without it we would look up `ConfigOptions`, which is an interface and therefore nothing at all once the code runs.

- Notice the `import type` on the interface, next to a normal import for the constant. With `emitDecoratorMetadata` on, a type named in a decorated signature must be imported as a type, or Deno stops at `TS1272`. The reverse holds for classes you inject by type : those must exist at runtime, so `import type` on a service is the fastest way to get told it is not available in injection context.

- Tokens are strings today. Using a class as a token works when the code runs, but the type says `string`, so TypeScript will argue with you. String constants keep things quiet.

## The rule nobody tells you

Injectables are resolved in the order you declare them, and that order is not decorative.

```ts src/app.module.ts
injectables: [
  ConfigService,
  { token: CONFIG_OPTIONS, useValue: options },
]
```

That boots straight into `TypeError: actualType is not a constructor`, which is not the most helpful message we ever wrote. What happens is that `ConfigService` is resolved first, we look for something registered under `CONFIG_OPTIONS`, we find your options object, and we try to `new` it.

Put the value first and everything is fine :

```ts src/app.module.ts
injectables: [
  { token: CONFIG_OPTIONS, useValue: options },
  ConfigService,
]
```

`useClass` and plain classes do not care about order, only `useValue` does. When a module refuses to boot on a token you are sure you registered, look at the array before you look at anything else.

## Configuration you do not have at import time

> But Thomas, my folder comes from an environment variable, I cannot write it in a decorator !

Then the module has to be built when the application starts rather than when the file is read. That is a dynamic module : a static method returning the same metadata object the decorator takes, plus a `module` property naming itself.

```ts src/config/config.module.ts
import { DynamicModule, Module } from 'jsr:@danet/core';
import { ConfigService } from './config.service.ts';
import { CONFIG_OPTIONS } from './constant.ts';
import type { ConfigOptions } from './constant.ts';

@Module({})
export class ConfigModule {
  static forRoot(options: ConfigOptions): DynamicModule {
    return {
      module: ConfigModule,
      injectables: [
        { token: CONFIG_OPTIONS, useValue: options },
        ConfigService,
      ],
    };
  }
}
```

```ts src/app.module.ts
import { Module } from 'jsr:@danet/core';
import { ConfigModule } from './config/config.module.ts';
import { TodoController } from './todo/todo.controller.ts';

@Module({
  imports: [ConfigModule.forRoot({
    folder: Deno.env.get('CONFIG_FOLDER') ?? './config',
    cacheTtl: 60,
  })],
  controllers: [TodoController],
})
export class AppModule {}
```

This is exactly how `KvQueueModule.forRoot()` takes a database path and how `ThrottlerModule.forRoot()` takes its limits. Nothing magic happens in either of them, they build the array you would have written by hand.

One thing that surprises people coming from Nest : our modules do not encapsulate. There is no `exports` key, because there is nothing to export. Once an injectable has been resolved it is available to anything that asks for it. Modules here group and order your code, they do not fence it.

## Scopes, and why you rarely need them

By default everything is a singleton, built once at bootstrap and shared. Deno does not hand each request to its own thread, so there is no thread to be unsafe across, and a shared instance is simply the right answer. That is why the connection pool in [the Postgres article]({{site.baseurl}}{% post_url 2024-08-09-postgres-in-danet-v2 %}) can be one object for the whole application.

Occasionally you want an object that belongs to one request : a correlation id, the current tenant, a per-request cache.

```ts src/context/request-context.service.ts
import { HttpContext, Injectable, SCOPE } from 'jsr:@danet/core';

@Injectable({ scope: SCOPE.REQUEST })
export class RequestContextService {
  public readonly requestId = crypto.randomUUID();
  public path = '';

  beforeControllerMethodIsCalled(ctx: HttpContext) {
    this.path = new URL(ctx.req.url).pathname;
  }
}
```

Few key points :

- The enum is `SCOPE`, in capitals, and its members are `GLOBAL`, `REQUEST` and `TRANSIENT`. `GLOBAL` is the default and never needs writing.

- `beforeControllerMethodIsCalled` is how a request-scoped injectable gets the context, and it can be async. It runs before your handler, on the instance built for that request.

- Scope bubbles upwards. Inject that service in a controller and the controller becomes request-scoped too, rebuilt on every call, because it cannot hold a fresh dependency inside a stale instance. Its other dependencies stay singletons.

- You do not declare scope on a controller. `@Controller()` takes a path and nothing else ; a controller is request-scoped when one of its dependencies is, and a singleton the rest of the time.

Request scope costs you one construction per request per class. That is small, but it is not zero, and it is very easy to make it the default without noticing. Reach for it when the object genuinely belongs to the request, and leave everything else alone.

Well, that's it folks ! It wasn't hard, now you know !

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

And the GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
