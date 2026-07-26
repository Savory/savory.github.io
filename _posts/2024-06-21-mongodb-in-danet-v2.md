---
published: true
title: Use MongoDB in Deno with Danet
excerpt: Get ready to use MongoDB in Danet in few minutes ! Spoiler, you have a lot less code to write than you used to.
---

![danet-logo.svg]({{site.baseurl}}/assets/images/danet-logo.svg)

Welcome ! Today's article is here to help you add a MongoDB connection to your Danet's API.

[We already wrote this one in 2022]({{site.baseurl}}{% post_url 2022-10-16-mongodb-in-danet %}), and back then we asked you to write a `MongoDBService` by hand, wire it into a `DatabaseModule`, and manage the connection yourself. You can forget all of that. We have a database package now.

We assume that you already have a MongoDB database available, either locally ([documentation here](https://www.mongodb.com/docs/manual/installation/)) or on a remote server/cloud provider, such as [MongoDB Atlas](https://www.mongodb.com/atlas/database?tck=docs_server) which has an awesome free tier.

## Import the module, that's it

Our [database module](https://jsr.io/@danet/database) handles the boring part. Import `MongodbModule` in your `app.module.ts` :

```ts src/app.module.ts
import { Module } from 'jsr:@danet/core';
import { MongodbModule } from 'jsr:@danet/database/mongodb';
import { TodoModule } from './todo/module.ts';

@Module({
  imports: [MongodbModule, TodoModule],
})
export class AppModule {}
```

That's the whole setup. `MongodbService` is now available anywhere in your app.

Danet needs to know where your server is, so give it the following environment variables : `DB_NAME`, `DB_HOST` and `DB_PORT`. `DB_USERNAME` and `DB_PASSWORD` are optional, but you really should use them. Deno supports `.env` files natively, so a `.env` file at your project's root works too.

Remember why we made the service a Singleton in 2022 ? Because the connection is shared among all our services, and because we want to connect once when the app starts and close when it stops. That reasoning did not change, we just don't make you implement it anymore : `MongodbService` implements the [lifecycle hooks](https://danet.land/fundamentals/lifecycle.html) `onAppBootstrap` and `onAppClose` for you.

## Repositories

Here is the part that saves you the most typing. In 2022 you wrote every single query by hand. Now each provider exports an abstract repository class you can extend :

```ts src/todo/repository.ts
import { Injectable } from 'jsr:@danet/core';
import { MongodbRepository, MongodbService } from 'jsr:@danet/database/mongodb';
import { Todo } from './class.ts';

@Injectable()
export class TodoRepository extends MongodbRepository<Todo> {
  constructor(protected service: MongodbService) {
    super(service, 'todos');
  }
}
```

Six lines, and you get `getAll`, `getById`, `create`, `updateOne`, `deleteOne` and `deleteAll`. The second argument of `super()` is the collection name.

Few key points :

- You extend `MongodbRepository<T>`, you do not implement the `Repository<T>` interface by hand anymore.

- MongoDB's flavour adds a bit on top of the shared interface : `getAll` accepts an optional filter, and you get an extra `getOne` method that takes a filter too. Both come from [the mongo driver](https://jsr.io/@db/mongo).

- Need a query the abstract class does not cover ? Add a method to your repository and use `this.service` directly. You are not locked in.

- Inject `TodoRepository` into your `TodoService` and your controller never knows a database exists. That was the advice in 2022 and it is still the advice today.

## The lazy way

If you are starting a fresh project, you do not even have to do any of this. Answer **MongoDB** when [the CLI asks you]({{site.baseurl}}{% post_url 2024-03-15-how-to-build-an-api-in-deno-with-danet-v2 %}) during `danet new`, and you get the module, a repository and a working CRUD out of the box.

Well, that's it folks ! It wasn't hard, now you know !

The same package handles Deno KV. To learn how to use Postgres in Danet, check [this article out]({{site.baseurl}}{% post_url 2024-08-09-postgres-in-danet-v2 %}), it plays by slightly different rules.

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

The GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
