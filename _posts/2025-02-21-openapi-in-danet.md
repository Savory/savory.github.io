---
published: true
title: Documenting your API with OpenAPI
excerpt: Your Danet app already serves a Swagger UI. Today we make it say something useful.
---

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)

Welcome ! At the end of [our body validation article]({{site.baseurl}}{% post_url 2024-05-03-body-validation-in-danet-v2 %}) we promised that both validation styles feed the OpenAPI generator, and that it was a subject for another day. Today is another day.

Before anything else, the disclaimer we owe you : the `SwaggerModule` is still in **Alpha** and maaaany features are missing. If something you need is not there, [file an issue](https://github.com/Savory/Danet-Swagger/issues) and we will look at it.

## You already have it

If you created your project with `danet new`, open [http://localhost:3000/api](http://localhost:3000/api) right now. The UI is there, because `bootstrap.ts` already does this :

```ts src/bootstrap.ts
import { DanetApplication } from 'jsr:@danet/core';
import { SpecBuilder, SwaggerModule } from 'jsr:@danet/swagger';
import { AppModule } from './app.module.ts';

export const bootstrap = async () => {
  const application = new DanetApplication();
  await application.init(AppModule);

  const spec = new SpecBuilder()
    .setTitle('Todo')
    .setDescription('The todo API')
    .setVersion('1.0')
    .build();
  const document = await SwaggerModule.createDocument(application, spec);
  await SwaggerModule.setup('api', application, document);

  return application;
};
```

`SpecBuilder` builds the base document, `createDocument()` walks your controllers and fills in every route it finds, and `setup()` mounts the UI on the path you give it. Want the raw spec instead of the UI ? It is on `/api/json`, ready to be fed to a client generator.

Nothing else in this article is required. It is all about making the generated document worth reading.

## Making your models show up

The generator reflects on your `@Body()` and `@Query()` decorators to find the shape of your payloads. It will not, however, guess which properties matter. Annotate them with `@ApiProperty()` :

```ts src/todo/class.ts
import { ApiProperty, Optional } from 'jsr:@danet/swagger';

export class Todo {
  @ApiProperty()
  public title!: string;

  @ApiProperty()
  public content!: string;

  @Optional()
  @ApiProperty()
  public _id?: string;
}
```

Few key points :

- No `@ApiProperty()`, no property in the documentation. The decorator is what makes it visible.

- `@Optional()` marks a property as not required.

- Enums need a hand, because the type is gone by the time we look : `@ApiProperty({ enum: ['Admin', 'Moderator', 'User'] })`.

- If reflection guesses wrong, override it with `@BodyType(Todo)` or `@QueryType(Todo)` on the handler.

## Return types

For a single object, just type your method and you are done. Danet reads the return type and generates the model :

```ts
@Get(':id')
async getById(@Param('id') id: string): Todo {
  return this.todoService.getById(id);
}
```

Arrays are where it gives up, because an array's element type does not survive reflection. Tell it explicitly with `@ReturnedType`, passing `true` as the second argument :

```ts
@ReturnedType(Todo, true)
@Get()
async getAll(): Todo[] {
  return this.todoService.getAll();
}
```

That second argument is the one everybody forgets. Without it you document an endpoint that returns one todo when it actually returns all of them.

## Tags and descriptions

A flat list of twenty endpoints is not documentation, it is a directory. Group them with `@Tag()`, on a controller or on a single route, and explain them with `@Description()` :

```ts src/todo/controller.ts
@Tag('todo')
@Controller('todo')
export class TodoController {
  @Description('Get a single Todo by its ID')
  @Get(':id')
  async getById(@Param('id') id: string): Todo {
    return this.todoService.getById(id);
  }
}
```

We love descriptions. Write descriptions.

## Documenting your auth

[Our API is protected by a JWT guard]({{site.baseurl}}{% post_url 2024-09-27-jwt-auth-in-danet %}), and right now the documentation says nothing about it, so anyone trying your endpoints from the UI gets denied and has no idea why.

Declare the scheme on the spec, then point your controllers at it :

```ts src/bootstrap.ts
const spec = new SpecBuilder()
  .setTitle('Todo')
  .addSecurity('bearer', {
    type: 'http',
    scheme: 'bearer',
    bearerFormat: 'JWT',
  })
  .build();
```

```ts src/todo/controller.ts
@ApiSecurity('bearer')
@Controller('todo')
export class TodoController {}
```

Basic auth is common enough that it has a shortcut on both sides, `.addBasicAuth()` on the builder and `@ApiBasicAuth()` on the controller.

## If you went the Zod way

Zod schemas work too, with one bit of setup. Extend Zod once, then give each schema a title so we know what to call the model :

```ts
import { extendZodWithOpenApi } from 'zod-openapi';

extendZodWithOpenApi(z);

const Todo = z.object({
  title: z.string(),
  content: z.string().min(20),
}).openapi({ title: 'Todo' });
```

Without that `title`, your model shows up unnamed and the document is much less pleasant to read.

Well, that's it folks ! It wasn't hard, now you know !

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

And the GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
