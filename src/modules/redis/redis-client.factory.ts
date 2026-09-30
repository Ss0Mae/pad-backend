import Redis, { RedisOptions } from 'ioredis';
import { RedisConfig } from '@config/redis.config';

export function createRedisClient(extra: RedisOptions = {}): Redis {
  const common: RedisOptions = {
    password: RedisConfig.password,
    commandTimeout: RedisConfig.commandTimeout,
    ...extra,
  };
  if (RedisConfig.sentinels.length) {
    return new Redis({
      ...common,
      sentinels: RedisConfig.sentinels,
      name: RedisConfig.masterName,
      failoverDetector: RedisConfig.failoverDetector,
    });
  }
  return new Redis({ ...common, host: RedisConfig.host, port: RedisConfig.port });
}
