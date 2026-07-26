---
published: true
title: Use Postgres in Deno with Danet
excerpt: Get ready to use Postgres in Danet in few minutes ! This one is the odd cousin of the database family, and that makes it a great excuse to learn custom injectables.
---

![danet-logo.svg]({{site.baseurl}}/assets/images/danet-logo.svg)

Welcome ! Today's article is here to help you add a Postgres connection to your Danet's API.

Small confession before we start : [the 2022 version of this article]({{site.baseurl}}{% post_url 2022-10-16-postgres-in-danet %}) told you to go install MongoDB and use the mongo driver. Copy-paste is a hell of a drug. Let's do it properly this time.

We assume you already have a Postgres server available, either locally ([documentation here](https://www.postgresql.org/download/)) or on a remote server/cloud provider.

## Why this one is different

[Last time]({{site.baseurl}}{% post_url 2024-06-21-mongodb-in-danet-v2 %}), MongoDB was three lines : import `MongodbModule`, done. Our [database package](https://jsr.io/@danet/database) currently ships two providers, **MongoDB** and **Deno KV**. Postgres is not one of them.

So for Postgres, you still write the plumbing yourself. Good news : that plumbing is about 30 lines, and writing it teaches you the pattern you will reuse every time you need to share a connection, a client, or anything else across your whole app.

We will use the Denodrivers' Postgres driver : [https://jsr.io/@db/postgres](https://jsr.io/@db/postgres)

## The service

In most cases, the database's connection is shared among all our services in our code, so our `PostgresService` will be a Singleton. That is Danet's default, nothing to do.

We also need to connect to our database server only once, when the app starts, and to close the connection when our app stops. In order to do this, we can use the `onAppBootstrap` and `onAppClose` lifecycle hooks !

```ts src/database/postgres.service.ts
import { Injectable, OnAppBootstrap, OnAppClose } from 'jsr:@danet/core';
import { Pool, PoolClient } from 'jsr:@db/postgres';

@Injectable()
export class PostgresService implements OnAppBootstrap, OnAppClose {
  private pool!: Pool;

  onAppBootstrap() {
    this.pool = new Pool({
      database: Deno.env.get('DB_NAME'),
      hostname: Deno.env.get('DB_HOST'),
      port: Number(Deno.env.get('DB_PORT')),
      user: Deno.env.get('DB_USERNAME'),
      password: Deno.env.get('DB_PASSWORD'),
    }, 5, true);
  }

  async onAppClose() {
    await this.pool.end();
  }

  async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      return await fn(client);
    } finally {
      client.release();
    }
  }
}
```

Few key points :

- The service implements `OnAppBootstrap` and `OnAppClose` to use lifecycle hooks. If you are coming from V1, note that `onAppShutdown` is now `onAppClose`, and it only fires if you explicitly call `app.close()`.

- The connection settings are read using `Deno.env.get`. Deno reads `.env` files natively, so a `.env` at your project's root works too. We use the same variable names as the rest of Danet : `DB_NAME`, `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`.

- We use a `Pool`, not a single `Client`. The 2022 article shared one client across every request, which is fine right up until two requests overlap. A pool hands each request its own connection and takes it back after. The `withClient` helper makes sure `release()` always happens, even when your query throws.

## The module

Now, we need to create a `DatabaseModule` to keep our code clean :

```ts src/database/module.ts
import { Module } from 'jsr:@danet/core';
import { PostgresService } from './postgres.service.ts';

@Module({
  injectables: [PostgresService],
})
export class DatabaseModule {}
```

Import this module in your `AppModule`, and use `PostgresService` wherever you need it. Danet's modules do not encapsulate their injectables today, so once `PostgresService` has been resolved it is available across the app.

## The repository

Here is a simplified `TodoRepository` :

```ts src/todo/repository.ts
import { Injectable } from 'jsr:@danet/core';
import { PostgresService } from '../database/postgres.service.ts';
import { Todo } from './class.ts';

@Injectable()
export class TodoRepository {
  constructor(private db: PostgresService) {}

  getAll(): Promise<Todo[]> {
    return this.db.withClient(async (client) => {
      const { rows } = await client.queryObject<Todo>`SELECT * FROM todo`;
      return rows;
    });
  }

  getById(id: string): Promise<Todo | undefined> {
    return this.db.withClient(async (client) => {
      const { rows } = await client.queryObject<Todo>`
        SELECT _id, title, content FROM todo WHERE _id = ${id}
      `;
      return rows[0];
    });
  }

  create(todo: Omit<Todo, '_id'>): Promise<Todo> {
    return this.db.withClient(async (client) => {
      const { rows } = await client.queryObject<Todo>`
        INSERT INTO todo (title, content)
        VALUES (${todo.title}, ${todo.content})
        RETURNING _id, title, content
      `;
      return rows[0];
    });
  }
}
```

Look carefully at those queries, because this is the one thing the 2022 article got dangerously wrong. It wrote them like this :

```ts
// DO NOT DO THIS
client.queryObject<Todo>(`SELECT * FROM TODO WHERE _id = '${id}'`)
```

That is a plain string with your user's input glued into it, which is a SQL injection waiting to happen. Send an `id` of `' OR 1=1 --` and see what you get back.

The version above uses `queryObject` as a **tagged template**. It looks almost identical, but the driver turns every `${}` into a real query parameter instead of pasting text. Same ergonomics, none of the danger. Drop the parentheses, keep your database.

## The lazy way

Starting fresh ? `danet new --postgres` generates the service, the module and a working CRUD for you. Same for the flag-less version, the CLI will just ask.

Well, that's it folks ! It wasn't hard, now you know !

To learn how to use MongoDB in Danet, check [this article out]({{site.baseurl}}{% post_url 2024-06-21-mongodb-in-danet-v2 %})

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

The GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
