---
published: true
title: "Scaffolding Danet apps with the CLI"
excerpt: "One CLI to rule them all."
---

![danet-logo.svg]({{site.baseurl}}/assets/images/danet-logo.svg)

Welcome ! We have been calling `danet new` since [the very first article]({{site.baseurl}}{% post_url 2024-03-15-how-to-build-an-api-in-deno-with-danet-v2 %}) without ever stopping on it. Today we stop on it, and on the rest of the CLI.

Install it once, under whatever name you like. We call it `danet` :

```bash
deno install --allow-read --allow-write --allow-run --allow-env --global -n danet jsr:@danet/cli
```

## A new project

```bash
danet new my-danet-project
cd my-danet-project
danet develop
```

`danet new` asks which database you want between `mongodb`, `postgres` and `in-memory`, then generates the matching code. Pass `--mongodb`, `--postgres` or `--in-memory` if you would rather not be asked.

What lands is a working Todo API, not an empty folder : `src/app.module.ts`, a controller, a service, a repository behind a token, a logger middleware, a Swagger spec built in `src/bootstrap.ts`, and a test in `spec/`. Open [http://localhost:3000](http://localhost:3000) and it answers.

## Three schematics

Then `danet generate`, `danet g` for short.

```bash
danet g module cat        # src/cat/module.ts      -> class CatModule
danet g controller cat    # src/cat/controller.ts  -> class CatController
danet g service cat       # src/cat/service.ts     -> class CatService
```

The aliases are `mo`, `co` and `s`. Each component gets its own folder, named after the feature rather than after the layer, because that is the convention the starter already follows.

The name you pass is normalised twice : kebab-case for the folder, PascalCase for the class. So `danet g co user-profile`, `danet g co userProfile` and `danet g co UserProfile` all write `src/user-profile/controller.ts` holding a `UserProfileController` mapped to the `user-profile` route.

What you get is empty.

```ts src/cat/controller.ts
import { Controller } from '@danet/core';

@Controller('cat')
export class CatController {
}
```

## The part that is worth the command

Creating a file is not much of a service, you have an editor for that. Registering it is the interesting half.

After those three commands, this is the module, and nobody typed it :

```ts src/cat/module.ts
import { Module } from '@danet/core';
import { CatController } from './controller.ts';
import { CatService } from './service.ts';

@Module({
  controllers: [CatController],
  injectables: [CatService]
})
export class CatModule {}
```

`danet g co cat` added the `controllers` entry and its import, `danet g s cat` added the `injectables` entry and its import. And `danet g mo cat` had already added the module itself to the root :

```ts src/app.module.ts
import { Module } from '@danet/core';
import { TodoModule } from './todo/module.ts';
import { AppController } from './app.controller.ts';
import { CatModule } from './cat/module.ts';

@Module({
  controllers: [AppController],
  imports: [TodoModule, CatModule],
})
export class AppModule {}
```

Few key points :

- **Generate the module first.** A controller looks for a `module.ts` next to it, a service does the same. If there is none, the file is still created and the wiring is skipped without an error, so nothing shouts at you. Module, then the rest.

- The rule is the one you would apply by hand : controllers go to `controllers`, services go to `injectables`, modules go to the `imports` of `src/app.module.ts`. Missing arrays are created.

- We edit through the TypeScript AST, not with a regular expression. Your formatting, your comments and your existing entries survive, and an entry already sitting in the array is left alone rather than added a second time. Do not count on that to re-run a generator though : if the file already exists, the command stops before it gets anywhere near your module.

- `--skip-import` turns the wiring off entirely. `--path` moves the folder elsewhere, and it moves the lookup with it : `danet g mo cat --path src/features` registers into `src/features/app.module.ts`, not into the root one.

- Generated imports use the bare `@danet/core` specifier, the one mapped in the `deno.json` that `danet new` gives you.

Nothing here is magic, and nothing here is mandatory. It is the same three arrays we unpacked in [the injector article]({{site.baseurl}}{% post_url 2025-10-24-dependency-injection-in-danet %}), filled in for you.

## Running and shipping

`danet develop` runs `run.ts` with file watching, `danet start` runs it without. `danet bundle` folds the whole module graph into one file, and `danet deploy` sends it to Deno Deploy in a single command, which is [its own article]({{site.baseurl}}{% post_url 2025-12-12-deploying-danet-to-deno-deploy %}).

Well, that's it folks ! It wasn't hard, now you know !

Documentation : [https://danet.land](https://danet.land)

Repository : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
