---
published: true
title: Body validation in Danet, two ways
excerpt: Welcome ! Last time, we saw how to build a REST API in Deno using Danet V2. Today, we will add Body validation to it. In V2, you have two ways of doing it.
---

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)

Welcome ! Last time, we saw [how to build a REST API in Deno using Danet V2]({{site.baseurl}}{% post_url 2024-03-15-how-to-build-an-api-in-deno-with-danet-v2 %}). Today, we will add Body validation to it.

[We wrote this article in 2022 too]({{site.baseurl}}{% post_url 2022-10-07-body-validation-in-danet %}), back then there was one way to do it. Now there are two, so let's look at both.

Let's start from the `todo.controller.ts` we ended up with :

```ts src/todo/controller.ts
@Post()
create(@Body() todo: Todo): Promise<Todo> {
  return this.todoService.create(todo);
}
```

As we can see, we indicate that to create a Todo, we need to do a POST request and send a `Todo`-ish object in the body. We get this object by using the `@Body` decorator.

However, the body format is not validated anywhere. Let's say we decided that a content should not be less than 20 characters. With the current code, I would be able to send the following body:

```json
{
  "title": 34,
  "content": "tooshort"
}
```

Notice that `title` is not a string and that `content`'s length is lower than 20 characters.

## Way 1 : decorate your class

This is the V1 way, and it still works exactly the same. Simply add `@Decorators` from [our validatte package](https://github.com/Savory/validatte) to your class :

```ts src/todo/class.ts
import { IsString, LengthGreater } from 'jsr:@danet/validatte';

export class Todo {
  public _id?: string;

  @IsString()
  public title!: string;

  @IsString()
  @LengthGreater(20)
  public content!: string;
}
```

By adding `@IsString()` and `@LengthGreater(20)`, we are attaching validators. You can see all the available decorators [here](https://github.com/Savory/validatte#available-decorators).

Under the hood, the `@Body` decorator gets the expected body type, and checks if there is any validator attached to the class attributes.
If there is, it calls the `validateObject()` function from `validatte` against the body.
If `validateObject` returns errors, an HTTP 400 is thrown with explicit errors :

```json
{
  "status": 400,
  "name": "NotValidBodyException",
  "reasons": [
    {
      "property": "content",
      "errorMessage": "Length must be greater than 20",
      "constraints": [
        20
      ]
    }
  ],
  "message": "400 - Body bad formatted"
}
```

If you are coming from V1, notice the response now carries a `name` and a `message` on top of the `reasons` array. Nothing to change on your side, your error handling just gets a bit more to work with.

One thing that is easy to miss : `@Body('person')` validates **only** that property against the expected type, not the whole body. Handy when your payload wraps the interesting part.

Two ways to import the decorators, by the way. Either from `jsr:@danet/validatte` like above, or from `jsr:@danet/core/validation`, which re-exports the whole package. Pick one and stay consistent.

## Way 2 : hand it a Zod schema

New in V2. If you already live in a Zod codebase, you don't have to translate your schemas into decorated classes. Import `@Body` from `jsr:@danet/zod` instead, and pass it the schema :

```ts src/todo/controller.ts
import { Controller, Post } from 'jsr:@danet/core';
import { Body } from 'jsr:@danet/zod';

const CreateTodoSchema = z.object({
  title: z.string(),
  content: z.string().min(20),
});

type CreateTodoSchema = z.infer<typeof CreateTodoSchema>;

@Controller('todo')
export class TodoController {
  constructor(private readonly todoService: TodoService) {}

  @Post()
  create(@Body(CreateTodoSchema) createTodoDto: CreateTodoSchema) {
    return this.todoService.create(createTodoDto);
  }
}
```

Same deal, the body gets validated against the schema before your method ever runs.

It works for query parameters too, which the decorator approach does not cover :

```ts
import { Query } from 'jsr:@danet/zod';

@Get(':id')
getById(@Query(GetTodoQuery) query: GetTodoQuery) {
  return this.todoService.getById(query.id);
}
```

## So, which one ?

We are not going to pick for you, but here is how we think about it :

- **Decorators** keep the class as the single source of truth. Your `Todo` is one file, it describes itself, and your controller signature stays clean. It is the most Danet-ish of the two.

- **Zod** gives you type inference from the schema, validation on query params, and access to everything already built around Zod. If your team writes schemas anyway, use it.

Both feed the OpenAPI generator, so you don't lose your Swagger documentation either way. That is a subject for another day.

Well, that's it folks ! It wasn't hard, now you know !

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

And the GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
