---
published: true
title: Real authentication with JWT guards in Danet
excerpt: We showed you a guard that checks a Basic auth header. Nobody ships that. Today we do it properly, with JWT.
---

![danet-logo.svg]({{site.baseurl}}/assets/images/danet-logo.svg)

Welcome ! When we [built our API]({{site.baseurl}}{% post_url 2024-03-15-how-to-build-an-api-in-deno-with-danet-v2 %}), we ended on Guards, and our example compared a header against a hardcoded Basic auth string. It made the point, but nobody ships that. Today we replace it with something you can actually put in production : JSON Web Tokens.

If you are not familiar with them, [jwt.io](https://jwt.io/) is the friendliest introduction. The short version : the client sends a signed token with every request, and the server verifies the signature instead of hitting a session store.

We will use [Jose](https://github.com/panva/jose), which works great in Deno through `npm:`.

## Signing a token

Our token is signed with a secret shared by the client and the server, using HMAC :

```ts jwt.ts
import { JWTPayload, SignJWT } from 'npm:jose@5.9.6';

// In real life this lives in an env variable, not in your source
const secret = new TextEncoder().encode(Deno.env.get('JWT_SECRET')!);

export function createJWT(payload: JWTPayload): Promise<string> {
  return new SignJWT(payload)
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(secret);
}
```

A word of honesty before we go further. HMAC uses **one** secret for signing and verifying, which means everyone who can verify a token can also forge one. The proper setup is a private/public key pair (RSA or ECDSA) : the server signs with the private key, everyone else verifies with the public one, and a leaked public key costs you nothing. Jose does both. We are showing HMAC because it is conceptually easier to start with, not because it is what you want.

## The guard

A guard is a class annotated with `@Injectable()` that implements the `AuthGuard` interface. It has a single responsibility : decide whether a request gets through.

```ts jwt-auth-guard.ts
import { AuthGuard, ExecutionContext, Injectable } from 'jsr:@danet/core';
import { JWTPayload, jwtVerify } from 'npm:jose@5.9.6';

const secret = new TextEncoder().encode(Deno.env.get('JWT_SECRET')!);

@Injectable()
export class JwtAuthGuard implements AuthGuard {
  async verifyJWT(token: string): Promise<JWTPayload | null> {
    try {
      const { payload } = await jwtVerify(token, secret);
      return payload;
    } catch {
      return null;
    }
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const authHeader = context.req.raw.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return false;
    }
    const payload = await this.verifyJWT(authHeader.slice('Bearer '.length));
    return payload !== null;
  }
}
```

Few key points :

- `canActivate()` returns a boolean, synchronously or as a Promise. `true` and the request is processed, `false` and Danet denies it. That is the whole contract.

- `context.req` is [Hono's request](https://hono.dev/api/request), so `context.req.raw.headers` is a plain web `Headers` object. If you are porting a V1 guard, this is the line that changes, `context.request` became `context.req`.

- **Check the header exists before touching it.** `headers.get()` returns `string | null`. Calling `.replace()` or `.slice()` on a missing header throws, and your guard answers an unauthenticated request with a 500 instead of a clean denial. That `?.startsWith('Bearer ')` is doing real work.

- Swallow the verification error and return `null`. An expired or tampered token is a normal event, not an exceptional one, and you do not want the details leaking into your response.

## Attaching it, the safe way

You can attach a guard to one controller or one route with `@UseGuard(JwtAuthGuard)`. Please don't, not for authentication.

The moment authentication is opt-in, forgetting to opt in leaves a route wide open, and nothing tells you. The failure is silent, and you find out about it from someone else. So we do the opposite : lock everything, then explicitly open what should be public.

Register the guard globally :

```ts src/app.module.ts
import { GLOBAL_GUARD, Module } from 'jsr:@danet/core';
import { JwtAuthGuard } from './jwt-auth-guard.ts';

@Module({
  injectables: [
    { useClass: JwtAuthGuard, token: GLOBAL_GUARD },
  ],
})
export class AppModule {}
```

*Every route* now means every route, including the login endpoint that hands out the tokens. That is the point, and we fix it with a decorator rather than by poking holes in the registration.

## The `@Public()` decorator

Danet gives you `SetMetadata` to attach arbitrary metadata to a class or a method, so our whitelist decorator is two lines :

```ts public.decorator.ts
import { SetMetadata } from 'jsr:@danet/core/metadata';

export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
```

Then the guard checks for it before doing any work :

```ts jwt-auth-guard.ts
import { MetadataHelper } from 'jsr:@danet/core/metadata';
import { IS_PUBLIC_KEY } from './public.decorator.ts';

async canActivate(context: ExecutionContext): Promise<boolean> {
  const isPublic = MetadataHelper.getMetadata<boolean>(
    IS_PUBLIC_KEY,
    context.getHandler(),
  ) ?? MetadataHelper.getMetadata<boolean>(IS_PUBLIC_KEY, context.getClass());

  if (isPublic) {
    return true;
  }

  const authHeader = context.req.raw.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return false;
  }
  const payload = await this.verifyJWT(authHeader.slice('Bearer '.length));
  return payload !== null;
}
```

`ExecutionContext` hands you `getHandler()`, the method about to run, and `getClass()`, the controller it belongs to. We look at both, so `@Public()` works on a single route or on an entire controller.

And now your login route says what it is :

```ts src/auth/controller.ts
@Controller('auth')
export class AuthController {
  @Public()
  @Post('login')
  login(@Body() credentials: Credentials) {
    // hand out a token
  }
}
```

Notice how the failure modes flipped. Forget `@UseGuard` and you ship an unprotected endpoint that behaves perfectly in testing. Forget `@Public()` and your login route returns a denial on the first request anyone makes. Annoying, obvious, fixed in a minute. Always choose the mistake that is loud.

## Trying it out

Generate yourself a token, then :

```bash
curl -H "Authorization: Bearer <your token here>" localhost:3000/todo
```

Without the header, or with a token you made up, you get denied. With a valid one, you get your todos.

Well, that's it folks ! It wasn't hard, now you know !

Because a guard is just an injectable, it can have dependencies. Inject a `UserService` into it and you can go from "this token is valid" to "this user is allowed to do this", which is where roles and permissions live.

To learn more about Danet, check out our documentation : [https://danet.land](https://danet.land)

And the GitHub repository if you want to contribute : [https://github.com/Savory/Danet](https://github.com/Savory/Danet)
