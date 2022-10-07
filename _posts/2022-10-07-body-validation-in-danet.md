---
published: true
title: Body validation in Danet
---

Welcome ! Last time, we saw [how to create a REST API in Deno using Danet]({{site.baseurl}}{% post_url 2022-08-28-how-to-build-an-api-with-danet %}). Today, we will add Body validation to it.

![deno logo.png]({{site.baseurl}}/assets/images/deno logo.png)


In order to add Body validation to your app, simply add `@Decorators` from [our validatte package](https://github.com/Savory/validatte) to your classes !

Let's look at the `todo.controller.ts` :

{% gist 2ccdbfce179625283cc206c1057d22c9 %}

As we can see, we indicate that to create Todo, we need to do a POST request and send a `Todo`-ish object in the body. We get this object by using the `@Body` decorator.

However, the body format is not validated anywhere. Let's say we decided that a description should not be less than 20 characters. With the current code, I would be able to send the following body:
```json
{
  "title": 34,
  "content": "tooshort"
}
```

Notice that `title` is not a string and that `content`'s length is lower than 20 characters.

To enforce our body format, we simply need to slightly change our `todo.class.ts` as following : 


{% gist 6bd47c3a721a1e2adb17eb9fc98fb006 %}

By adding `@IsString()` and `@LengthGreater(20)`, we are attaching validators.

Under the hood, the `@Body` decorator get the expected body type, and check if there is any validators attached to the class attributes.
If there is, it calls `validateObject()` function from `validatte` against the body.
If `validateObject` returns errors, an HTTP 400 BadRequest is thrown with explicit errors :

```json
{
  "status": 400,
  "reasons":
  [
    {
      "property": "content",
      "errorMessage": "Length must be greater than 20",
      "constraints": [
        20
      ]
    }
  ]
}
```

Well, that's it folks ! It wasn't hard, now you know !
