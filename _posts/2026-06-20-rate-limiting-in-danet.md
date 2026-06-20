---
published: true
title: "Rate limiting in Danet"
excerpt: "Your API is public, and someone is going to hammer your login route until something gives. Ten requests a minute, one guard, one gotcha : ttl is in milliseconds."
---

![danet-logo.svg]({{site.baseurl}}/assets/images/danet-logo.svg)

Welcome ! Your API is public, and sooner or later someone hammers your login route until something gives. Today we cap how fast anyone is allowed to talk to us.

Nothing to install. Danet ships a throttler inside `@danet/core` since 2.10.0, built on top of guards and modeled after `@nestjs/throttler`.

## Ten requests a minute

```ts src/app.module.ts
import {
  GLOBAL_GUARD,
  Module,
  ThrottlerGuard,
  ThrottlerModule,
} from 'jsr:@danet/core';
import { TodoModule } from './todo/todo.module.ts';

@Module({
  imports: [
    TodoModule,
    ThrottlerModule.forRoot([{ ttl: 60000, limit: 10 }]),
  ],
  injectables: [
    { useClass: ThrottlerGuard, token: GLOBAL_GUARD },
  ],
})
export class AppModule {}
```

Few key points :

- `ttl` is expressed in **milliseconds**. `60000` is one minute. Write `ttl: 60` because you were thinking in seconds and you get a window of sixty milliseconds, which is a very permissive rate limit that never triggers and never explains itself.

- The registration is the V2 syntax : a plain `{ useClass, token }` object under the `GLOBAL_GUARD` token, the one we unpacked in [the injector article]({{site.baseurl}}{% post_url 2025-10-24-dependency-injection-in-danet %}).

- Counters are **per route**, not per application. The storage key is built from the throttler name, the caller, the controller class and the method name, so ten calls to `GET /todo` do not eat the budget of `GET /todo/:id`.

- The caller is identified by IP, reading `X-Forwarded-For` then `X-Real-IP` before falling back to the connection address. It survives a reverse proxy.

Every response then carries `X-RateLimit-Limit`, `X-RateLimit-Remaining` and `X-RateLimit-Reset`. Once the limit is exceeded, Danet answers `429` with the usual exception body and adds `Retry-After`. Those two are in seconds, because headers are headers.

## Two exceptions you will want immediately

A health check should never be throttled, and a login route should be throttled harder than the rest.

```ts src/health/health.controller.ts
import { Controller, Get, SkipThrottle } from 'jsr:@danet/core';

@Controller('health')
@SkipThrottle()
export class HealthController {
  @Get('/')
  check() {
    return 'OK';
  }
}
```

```ts src/auth/auth.controller.ts
import { Controller, Get, Throttle } from 'jsr:@danet/core';

@Controller('auth')
export class AuthController {
  @Throttle({ default: { ttl: 60000, limit: 5 } })
  @Get('login')
  login() {
    return 'OK';
  }
}
```

Both decorators work on a controller or on a single handler. `default` is the name your throttler gets when you did not give it one.

> But Thomas, my global guard is already taken !

It is, yes. In [the JWT article]({{site.baseurl}}{% post_url 2024-09-27-jwt-auth-in-danet %}) we registered an authentication guard under that exact token, and there is only one slot. Declare two, and the last one silently wins : you keep either your rate limit or your authentication, and nothing warns you which.

So stack them by inheritance instead.

```ts src/auth/jwt-auth.guard.ts
import { ExecutionContext, Injectable, ThrottlerGuard } from 'jsr:@danet/core';

@Injectable()
export class JwtAuthGuard extends ThrottlerGuard {
  // isPublic() and verifyJWT() are the ones from the JWT article,
  // moved into methods to keep this readable.

  override async canActivate(context: ExecutionContext): Promise<boolean> {
    await super.canActivate(context);

    if (this.isPublic(context)) {
      return true;
    }

    const authHeader = context.req.raw.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return false;
    }
    const payload = await this.verifyJWT(authHeader.slice('Bearer '.length));
    return payload !== null;
  }
}
```

Call `super.canActivate()` **first**. It throws a `ThrottlerException` when the caller is over the limit, so an abusive client gets its `429` before you spend a signature verification on it, and your `@Public()` routes stay rate limited too.

The subclass inherits the constructor, so the throttler options and the storage are still injected for you. Register `JwtAuthGuard` as `GLOBAL_GUARD` and you are done.

If you need to key on something other than an IP, an API key for instance, override `getTracker()` :

```ts src/auth/jwt-auth.guard.ts
// still inside JwtAuthGuard
protected override getTracker(context: ExecutionContext): string {
  return context.req.header('x-api-key') ?? super.getTracker(context);
}
```

The `override` keyword is not optional, Deno type checks it.

## One honest limitation

Counts are kept in memory. That storage is process local, so two instances behind a load balancer each grant the full quota, and your limit of ten is really a limit of twenty. For a single deployment it is fine. For anything horizontal, implement the `ThrottlerStorage` interface on Deno KV or Redis and pass it as the second argument of `forRoot()`.

Well, that's it folks ! It wasn't hard, now you know !

Documentation : [https://danet.land](https://danet.land)

Repository : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
