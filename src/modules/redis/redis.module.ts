import { Module, Global } from '@nestjs/common';
import { RedisService } from './redis.service';
import { createRedisClient } from './redis-client.factory';

@Global()
@Module({
  providers: [
    {
      provide: 'REDIS_CLIENT',
      useFactory: () => createRedisClient(),
    },
    RedisService,
  ],
  exports: [RedisService],
})
export class RedisModule {}
