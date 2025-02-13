#!/usr/bin/env -S deno -q run --allow-net
import { ServerSentEvent, ServerSentEventTarget } from 'jsr:@oak/commons@^1.0/server_sent_event';
import { Application } from 'jsr:@oak/oak/application';
import { Router } from "jsr:@oak/oak/router";

const HTTP_PORT = 4815

const clients: Record<string, ServerSentEventTarget> = {}

function broadcast(cmd: string) {
  for (const [_, target] of Object.entries(clients)) {
    target.dispatchEvent(new ServerSentEvent(cmd))
  }
}

const router = new Router();
router.use((ctx, next) => {
  ctx.response.headers.set('Access-Control-Allow-Origin', '*')
  return next()
})
router.get("/sse", async (ctx) => {
  const target = await ctx.sendEvents();
  const id = crypto.randomUUID()
  clients[id] = target
  target.addEventListener('close', () => {
    delete clients[id]
  })
});
router.post('/unmute', () => {
  broadcast('unmute')
})
router.post('/mute', () => {
  broadcast('mute')
})
router.post('/no-mic', () => {
  broadcast('mute')
})

const app = new Application();
app.use(router.routes());
app.use(router.allowedMethods());

app.listen({ port: HTTP_PORT });
