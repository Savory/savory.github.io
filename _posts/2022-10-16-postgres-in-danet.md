---
published: true
title: Use Postgres in Deno with Danet
excerpt: Get ready to use Postgres in Danet in few minutes !
---

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)

Welcome ! Today's article is here to help you add a Postgres connection to your Danet's API.

We assume that you already have a MongoDB database available, either locally ([documentation here](https://www.mongodb.com/docs/manual/installation/)) or on a remote server/cloud provider, such as [MongoDB Atlas](https://www.mongodb.com/atlas/database?tck=docs_server) which has an awesome free tier.

To connect to our postgres database we will use the Denodrivers' mongo driver  : [https://deno.land/x/postgres](https://deno.land/x/postgres)

In most cases, the database's connection is shared among all our services in our code, our `PostgresService` will then be a Singleton.

We also need to connect to our Database Server only once, when the app starts, and we need to close the connection when our app stops. In order to do this, we can use `onAppBootstrap` and `onAppShutdown` lifecycle hooks !


Let's dive into the code now :

{% gist 13bc7ab4b90f39eeff60cff54f7d6f2b %}

For simplicity's sake, we are importing everything from urls. However, we recommend creating a `deps.ts` file to import/export everything. Doing so result in a single point of truth and an easier maintenance.

Few key points  :

- The service implement `OnAppBoostrap` and `OnAppShutdown` to use lifecycle hooks.

- The connection URI is created using `Deno.env.get` to get environment variables.

Now, we need to create a `DatabaseModule` to keep our code clean : 

{% gist 525636dab7fe70de009425b640a85814 %}


Import this module in any module that need your newly created `PostgresService`, and use it wherever you need.

Here is a simplified code from of our [Starter Repository](https://github.com/Savory/Danet-Starter) that contain all the necessary code to work Postgres AND MongoDb seamlessly: 

```ts
import { PostgresService } from "../database/postgresService.ts";

export class PostgresRepository implements Repository<Todo> {
  constructor(private dbService: PostgresService) {
  }
  async getAll(): Promise<Todo[]> {
    const { rows } = await this.dbService.client.queryObject<
      Todo
    >`SELECT * FROM TODO`;
    return rows;
  }

  async getById(id: string) {
    const { rows } = await this.dbService.client.queryObject<Todo>(
      `SELECT _id, title, content FROM TODO WHERE _id = '${id}'`,
    );
    return rows[0];
  }

  async create(todo: Omit<Todo, "_id">) {
    const { rows } = await this.dbService.client.queryObject<Todo>(
      `INSERT INTO TODO (title, content) VALUES ('${todo.title}', '${todo.content}') RETURNING _id, title, content;`,
    );
    return rows[0];
  }

  async updateOne(todoId: string, todo: Todo) {
    const { rows } = await this.dbService.client.queryObject<Todo>(
      `UPDATE TODO SET title = '${todo.title}', content = '${todo.content}' WHERE _id = '${todoId}' RETURNING _id, title, content;`,
    );
    return rows[0];
  }

  async deleteOne(todoId: string) {
    return this.dbService.client.queryObject<Todo>(
      `DELETE FROM TODO WHERE _id = '${todoId}';`,
    );
  }

  async deleteAll() {
    return this.dbService.client.queryObject<Todo>(`DELETE FROM TODO`);
  }
}
```


Well, that's it folks ! It wasn't hard, now you know !

To learn how to use MongoDB in Danet, check [this article out]({{site.baseurl}}{% post_url 2022-10-16-mongodb-in-danet %})

To learn more about Danet, check out our documentation : [https://savory.github.io/Danet/](https://savory.github.io/Danet/)

The GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
