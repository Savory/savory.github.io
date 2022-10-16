---
published: true
title: Use mongodb in Deno with Danet
excerpt: Get ready to use MongoDB in Danet in few minutes !
---

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)

Welcome ! Today's article is here to help you add a MongoDB connection to your Danet's API.

We assume that you already have a MongoDB database available, either locally ([documentation here](https://www.mongodb.com/docs/manual/installation/)) or on a remote server/cloud provider, such as [MongoDB Atlas](https://www.mongodb.com/atlas/database?tck=docs_server) which has an awesome free tier.

To connect to our mongodb database we will use the Denodrivers' mongo driver  : [https://deno.land/x/mongo@v0.31.1](https://deno.land/x/mongo@v0.31.1)

In most cases, the database's connection is shared among all our services in our code, our `MongoDBService` will then be a Singleton.

We also need to connect to our Database Server only once, when the app starts, and we need to close the connection when our app stops. In order to do this, we can use `onAppBootstrap` and `onAppShutdown` lifecycle hooks !


Let's dive into the code now :

{% gist 18d9871cf4f61f22e7e168b701b70b4d %}

For simplicity's sake, we are importing everything from urls. However, we recommend creating a `deps.ts` file to import/export everything. Doing so result in a single point of truth and an easier maintenance.

Few key points  :

- The service implement `OnAppBoostrap` and `OnAppShutdown` to use lifecycle hooks.

- The connection URI is created using `Deno.env.get` to get environment variables.

Now, we need to create a `DatabaseModule` to keep our code clean : 

{% gist 2d2b7ec77bfdc404304010802cd326e7 %}


Import this module in any module that need your newly created `MongoDBService`, and use it wherever you need.


Here is a simplified code from of our [Starter Repository](https://github.com/Savory/Danet-Starter) that contains all the necessary code to work with MongoDB AND Postgres seamlessly:

```ts
export class MongodbRepository implements Repository<Todo> {
  constructor(private dbService: MongoDBService) {
  }
  async getAll(): Promise<Todo[]> {
    return this.dbService.getCollection<Todo>("Todo").find({}).toArray();
  }

  async getById(id: string) {
    return this.dbService.getCollection<Todo>("Todo").findOne({
      _id: new ObjectId(id),
    });
  }

  async create(todo: Omit<Todo, "_id">) {
    const insertedId = await this.dbService.getCollection<Omit<Todo, "id">>(
      "Todo",
    ).insertOne(todo);
    return {
      _id: insertedId,
      ...todo,
    };
  }

  async updateOne(todoId: string, todo: Todo) {
    const objectId = new ObjectId(todoId);
    const updated = await this.dbService.getCollection<Todo>("Todo").updateOne(
      { _id: objectId },
      { $set: { ...todo } },
    );
    return updated;
  }

  async deleteOne(todoId: string) {
    return this.dbService.getCollection<Todo>("Todo").deleteOne({
      _id: new ObjectId(todoId),
    });
  }

  async deleteAll() {
    return this.dbService.getCollection<Todo>("Todo").deleteMany({});
  }
}

```

Well, that's it folks ! It wasn't hard, now you know !

To learn how to use Postgres in Danet, check [this article out]({{site.baseurl}}{% post_url 2022-10-16-postgres-in-danet %})

To learn more about Danet, check out our documentation : [https://savory.github.io/Danet/](https://savory.github.io/Danet/)

The GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
