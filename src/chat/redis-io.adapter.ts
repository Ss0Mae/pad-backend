import { INestApplicationContext, Logger } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { ServerOptions } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createRedisClient } from '@modules/redis/redis-client.factory';

// 서버가 여러 대일 때 방 브로드캐스트와 fetchSockets 가 다른 서버의 소켓까지 닿도록
// Socket.IO 이벤트를 Redis Pub/Sub 으로 서버 간에 전달한다.
export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor: ReturnType<typeof createAdapter>;

  constructor(app: INestApplicationContext) {
    super(app);
  }

  async connectToRedis(): Promise<void> {
    const pubClient = createRedisClient();
    const subClient = pubClient.duplicate();
    for (const [name, c] of [['pub', pubClient], ['sub', subClient]] as const) {
      c.on('error', e => this.logger.warn(`redis ${name} error: ${e.message}`));
      c.on('ready', () => this.logger.log(`redis ${name} ready ${(c as any).stream?.remoteAddress}:${(c as any).stream?.remotePort}`));
      c.on('reconnecting', () => this.logger.log(`redis ${name} reconnecting`));
      c.on('end', () => this.logger.log(`redis ${name} end`));
    }
    this.adapterConstructor = createAdapter(pubClient, subClient, {
      requestsTimeout: 3000,
    });
  }

  createIOServer(port: number, options?: ServerOptions) {
    const server = super.createIOServer(port, options);
    server.adapter(this.adapterConstructor);
    return server;
  }
}
