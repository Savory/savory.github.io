---
published: true
title: How to build an API in Deno with Danet (V2)
excerpt: Welcome, take a seat, and keep your keyboard at hand because today we are building a REST API in Deno using Danet V2. In the end, we'll also show you how to handle authentication.
---

Welcome, take a seat, and keep your keyboard at hand because today we are building a REST API in Deno using Danet. In the end, we'll also show you how to handle authentication.

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)

We wrote [this exact article back in 2022]({{site.baseurl}}{% post_url 2022-08-28-how-to-build-an-api-in-deno-with-danet %}). Danet was on V1, we were running on Oak, and we were publishing on `deno.land/x`. None of that is true anymore, so here is the same tutorial, rewritten from scratch for V2.

## What is Deno ?

Deno is a simple, modern, and secure runtime for JavaScript, TypeScript, and WebAssembly that uses V8 and is built in Rust.

1. Provides web platform functionality and adopts web platform standards.

2. Secure by default. No file, network, or environment access, unless explicitly enabled.

3. Supports TypeScript out of the box.

4. Ships only a single executable file.

5. Has built-in development tooling like a dependency inspector (deno info) and a code formatter (deno fmt).

You can learn more here on Deno's official website [https://deno.land/](https://deno.land/)

## What is Danet ?

Danet is an open-source framework. Nest was one of the greatest tools to improve architecture of NodeJS project. Danet wants to bring the same level of pro-efficiency and professionalism into Deno's world.

Exactly like Nest, Danet provides an out-of-the-box application architecture that allows developers and teams to create highly testable, scalable, loosely coupled, and easily maintainable applications.

It is entirely made in Typescript.

Two things changed since our first article :

- **We run on [Hono](https://hono.dev/) now.** V1 used Oak. We switched for the performance, and you can look at [our benchmark](https://quickchart.io/chart/render/sf-adcfeec7-78bc-43c6-9019-09c18ae3bd48) if you like charts.

- **We publish on [JSR](https://jsr.io/@danet/core) only**, since version 2.4.0. No more `deno.land/x` URLs, no more `deps.ts` juggling. It's a step closer to runtime agnosticism.

You can find the documentation here : [https://danet.land](https://danet.land)

And the GitHub repository : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)

## Installation

First thing first, we need Deno. Any recent Deno 2.x will do.

### Deno

Deno ships as a single executable with no dependencies. You can install it using the installers below, or download a release binary from the releases page.

#### Shell (Mac, Linux):
`curl -fsSL https://deno.land/install.sh | sh`

#### PowerShell (Windows):
`irm https://deno.land/install.ps1 | iex`

#### Homebrew (Mac):
`brew install deno`

See [deno_install](https://github.com/denoland/deno_install) for more installation options.

### Danet

In 2022 we told you to clone our starter repository. Forget that, we have a CLI now :

```bash
deno install --allow-read --allow-write --allow-run --allow-env --global -n danet jsr:@danet/cli
danet new my-danet-project
cd my-danet-project
```

`danet new` will ask you which database you want : MongoDB, Postgres, or a simple in-memory one. For this article, pick **in-memory**, we will cover the two others in dedicated articles.

## Basic tutorial

The generated project is a REST API for a to-do list. Here is how it looks:

```
my-danet-project
├── deno.json
├── run.ts
└── src
    ├── app.module.ts
    ├── bootstrap.ts
    └── todo
        ├── class.ts
        ├── controller.ts
        ├── module.ts
        └── service.ts
```

Notice something missing ? There is no `deps.ts` anymore. In V1, Deno had no dependency manifest, so we used a single file to re-export everything and pin our versions in one place. With JSR and the `imports` map in `deno.json`, Deno does that for us. One less file to maintain.

Let's go through each file.

### src/todo/class.ts

```ts src/todo/class.ts
export class Todo {
  public _id?: string;
  constructor(
    public title: string,
    public content: string,
  ) {}
}
```

Simplest file, we define our Todo class.

### src/todo/controller.ts

```ts src/todo/controller.ts
import { Body, Controller, Delete, Get, Param, Post, Put } from 'jsr:@danet/core';
import { Todo } from './class.ts';
import { TodoService } from './service.ts';

@Controller('todo')
export class TodoController {
  constructor(public todoService: TodoService) {}

  @Get()
  getAll(): Promise<Todo[]> {
    return this.todoService.getAll();
  }

  @Get(':id')
  getById(@Param('id') id: string): Promise<Todo | undefined> {
    return this.todoService.getById(id);
  }

  @Post()
  create(@Body() todo: Todo): Promise<Todo> {
    return this.todoService.create(todo);
  }

  @Put(':id')
  updateOne(@Param('id') id: string, @Body() todo: Todo) {
    return this.todoService.updateOne(id, todo);
  }

  @Delete(':id')
  deleteOne(@Param('id') id: string) {
    return this.todoService.deleteOne(id);
  }
}
```

Controllers are responsible for handling incoming **requests** and returning **responses** to the client.

A controller's purpose is to receive specific requests for the application. The **routing** mechanism controls which controller receives which requests. Frequently, each controller has more than one route, and different routes can perform different actions.

In order to create a basic controller, we use classes and **decorators**. Decorators associate classes with required metadata and enable Danet to create a routing map (tie requests to the corresponding controllers).

We use the `@Controller()` decorator, which is **required** to define a basic controller. We'll specify an optional route path prefix of todo. Using a path prefix in a `@Controller()` decorator allows us to easily group a set of related routes, and minimize repetitive code. For example, we may choose to group a set of routes that manage interactions with a customer entity under the route /customers. In that case, we could specify the path prefix customers in the `@Controller()` decorator so that we don't have to repeat that portion of the path for each route in the file.

The `constructor(public todoService: TodoService)` uses **Dependency Injection**. Danet is built around this strong design pattern. We recommend reading a great article about this concept in the [official Angular documentation](https://angular.io/guide/dependency-injection).

Two V2 additions worth knowing while you are here : `@Context()` gives you Danet's `ExecutionContext` directly in your handler's signature, and `@HttpCode(204)` on a method changes the status code, which defaults to 200.

### src/todo/service.ts

```ts src/todo/service.ts
import { Injectable } from 'jsr:@danet/core';
import { Todo } from './class.ts';

@Injectable()
export class TodoService {
  private todos: Todo[] = [];

  getAll(): Promise<Todo[]> {
    return Promise.resolve(this.todos);
  }

  getById(id: string): Promise<Todo | undefined> {
    return Promise.resolve(this.todos.find((todo) => todo._id === id));
  }

  create(todo: Todo): Promise<Todo> {
    const created = { ...todo, _id: crypto.randomUUID() };
    this.todos.push(created);
    return Promise.resolve(created);
  }

  // updateOne, deleteOne, you get the idea
}
```

This service, which is automatically injected into `TodoController` thanks to the `@Injectable()` decorator, contains all our business logic.

For simplicity's sake, it only stores Todos in memory. However, for your real projects, storage should be handled by a `todoRepository` class injected into `TodoService`. That is exactly what you get if you answer MongoDB or Postgres to `danet new`.

### src/todo/module.ts

```ts src/todo/module.ts
import { Module } from 'jsr:@danet/core';
import { TodoController } from './controller.ts';
import { TodoService } from './service.ts';

@Module({
  controllers: [TodoController],
  injectables: [TodoService],
})
export class TodoModule {}
```

A module is a class annotated with a `@Module()` decorator. The `@Module()` decorator provides metadata that **Danet** makes use of to organize the application structure.
The `@Module()` decorator takes a single object whose properties describe the module:

- `injectables` the injectables that will be instantiated by the Danet injector and that may be shared at least across this module

- `controllers` the set of controllers defined in this module which have to be instantiated

- `imports` the list of imported modules that declare the injectables which are required in this module

Our application being fairly simple, we only have `TodoController` and `TodoService`.

Good news : you rarely have to edit this file by hand anymore. `danet g controller cat` creates the controller **and** adds it to the `controllers` array of its sibling module. Same for `danet g service`, and a generated module registers itself in your `app.module.ts`.

### src/app.module.ts

```ts src/app.module.ts
import { Module } from 'jsr:@danet/core';
import { TodoModule } from './todo/module.ts';

@Module({
  imports: [TodoModule],
})
export class AppModule {}
```

The AppModule imports all modules you want your application to use. In our case, `TodoModule` is sufficient.

### src/bootstrap.ts

```ts src/bootstrap.ts
import { DanetApplication } from 'jsr:@danet/core';
import { SpecBuilder, SwaggerModule } from 'jsr:@danet/swagger';
import { AppModule } from './app.module.ts';

export async function bootstrap() {
  const application = new DanetApplication();
  await application.init(AppModule);

  const spec = new SpecBuilder()
    .setTitle('Todo')
    .setDescription('The todo API')
    .setVersion('1.0')
    .build();
  const document = await SwaggerModule.createDocument(application, spec);
  SwaggerModule.setup('api', application, document);

  return application;
}
```

The `bootstrap` function creates a `DanetApplication` instance and initializes it with our `AppModule`. Behind the scene, it resolves and injects dependencies, creates route handlers, etc…

**This does not make the http server listen to any port yet.**

### run.ts

```ts run.ts
import { bootstrap } from './src/bootstrap.ts';

const application = await bootstrap();

let port = Number(Deno.env.get('PORT'));
if (isNaN(port)) {
  port = 3000;
}
application.listen(port);
```

It is the entry point of our app. This file is executed by Deno when we execute the `launch-server` task defined in `deno.json`.

`bootstrap` creates the `DanetApplication` instance, and we call `listen` to listen (not very explicit I know /s) on a given port either from env or default to 3000 (no specific reason).

### deno.json

```json deno.json
{
  "tasks": {
    "launch-server": "deno run --allow-net --allow-env --allow-read run.ts",
    "test": "deno test --allow-net --allow-env --allow-read spec/"
  },
  "imports": {
    "@danet/core": "jsr:@danet/core@^2.11.0",
    "@danet/swagger": "jsr:@danet/swagger"
  },
  "compilerOptions": {
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true
  }
}
```

Deno's configuration file.

It defines 2 tasks, `launch-server` and `test`, which means that you can execute `deno task launch-server` to run the server, and `deno task test` to run tests that are in the spec folder. During development, `danet develop` does the same thing with file watching.

The `imports` map is the part that replaced `deps.ts`. Pin your versions here, once, and import `@danet/core` everywhere else.

Let's take a second to talk about Deno's arguments:

- `allow-net` allow network access. You can specify an optional, comma-separated list of IP addresses or hostnames (optionally with ports) to provide an allow-list of allowed network addresses.

- `allow-env` Allow environment access for things like getting and setting environment variables. You can specify an optional, comma-separated list of environment variables to provide an allow-list of allowed environment variables.

- `allow-read` for file system read access. You can specify an optional, comma-separated list of directories or files to provide an allow-list of allowed file system access.

Full documentation is accessible here : [https://docs.deno.com/runtime/fundamentals/security/](https://docs.deno.com/runtime/fundamentals/security/)

## Swagger, for free

Run `deno task launch-server` and open [http://localhost:3000/api](http://localhost:3000/api).

Your API is already documented. That `SwaggerModule.setup('api', ...)` call in `bootstrap.ts` walks your controllers and generates an OpenAPI spec from your decorators. You did not write a line of YAML.

It is still in Alpha and many features are missing, so if something you need is not there, [open an issue](https://github.com/Savory/Danet-Swagger/issues).

That's it. You should have a REST API up and running !

> But Thomas, you told us we were going to see how to handle Authentication with Danet !

You are right pal, let's talk about

## Guards

A guard is a class annotated with the `@Injectable()` decorator, which implements the `AuthGuard` interface.

Guards have a **single responsibility**. They determine whether a given request will be handled by the route handler or not, depending on certain conditions (like permissions, roles, ACLs, etc.) present at run-time. This is often referred to as **authorization**.

Here is an over simplified example of a guard :

```ts simple-auth-guard.ts
import { AuthGuard, ExecutionContext, Injectable } from 'jsr:@danet/core';

@Injectable()
export class SimpleAuthGuard implements AuthGuard {
  validateRequest(authHeader: string | undefined): boolean {
    // Can be tested using: curl -u user:my-secret-password localhost:3000/todo
    return authHeader === 'Basic dXNlcjpteS1zZWNyZXQtcGFzc3dvcmQ=';
  }

  canActivate(context: ExecutionContext): boolean | Promise<boolean> {
    const authHeader = context.req.raw.headers.get('authorization');
    return this.validateRequest(authHeader);
  }
}
```

The logic inside the `validateRequest()` function can be as simple or sophisticated as needed. The main point of this example is to show how guards fit into the request/response cycle.

Every guard must implement a `canActivate()` function. This function should **return a boolean**, indicating whether the current request is allowed or not. It can return the response either synchronously or asynchronously via a Promise.

Danet uses the return value to control the next action:
if it returns true, the request will be processed.
if it returns false, Danet will deny the request.

Look closely at `context.req`. This is **the** breaking change of V2. In V1 our context was a superset of Oak's, so you wrote `context.request`. It is now a superset of [Hono's context](https://hono.dev/api/context), so it's `context.req` and `context.res`. If you are migrating an old app, this is very likely the only thing you have to fix.

Guards can be attached to a **Controller**, a **Method/Route**, or even registered as global guards (that will be used for **EVERY ROUTE**).

To attach it to our TodoController we just need to use the `@UseGuard()` decorator as following:

```ts
@Controller('todo')
@UseGuard(SimpleAuthGuard)
export class TodoController {
  // ...
}
```

You can set up a global guard by providing it to the `AppModule` the following way :

```ts app.module.ts
import { GLOBAL_GUARD, Module } from 'jsr:@danet/core';
import { SimpleAuthGuard } from './simple-auth-guard.ts';

@Module({
  injectables: [
    { useClass: SimpleAuthGuard, token: GLOBAL_GUARD },
  ],
})
export class AppModule {}
```

If you wrote this in V1, you remember `new TokenInjector(SimpleGuard, GLOBAL_GUARD)`. That still works, and you will still find it in the generated project, but it is deprecated : prefer the plain object above.

That's it folks !

Next time, we will add body validation to this API, the two ways you can do it in V2.

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

And the GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
