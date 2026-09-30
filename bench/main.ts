import { NestFactory } from '@nestjs/core';
import { BenchModule } from './bench.module';
import { RedisIoAdapter } from '@src/chat/redis-io.adapter';

async function bootstrap() {
  const app = await NestFactory.create(BenchModule, { logger: ['error', 'warn', 'log'] });
  if (process.env.CHAT_REDIS_ADAPTER !== 'off') {
    const a = new RedisIoAdapter(app);
    await a.connectToRedis();
    app.useWebSocketAdapter(a);
  }
  await app.listen(Number(process.env.PORT));
  console.log(`bench app on ${process.env.PORT} adapter=${process.env.CHAT_REDIS_ADAPTER !== 'off'}`);
}
bootstrap();
