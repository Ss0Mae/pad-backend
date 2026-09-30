import Redis, { Cluster, RedisOptions } from 'ioredis';
import { RedisConfig } from '@config/redis.config';

// 접속 모드는 환경 변수로 고른다. 우선순위: REDIS_CLUSTER_NODES > REDIS_SENTINELS > 단일 노드.
// Cluster 클라이언트는 duplicate()·publish/subscribe 를 그대로 지원해 Socket.IO Redis 어댑터에 넣을 수 있다.
export function createRedisClient(extra: RedisOptions = {}): Redis | Cluster {
  const common: RedisOptions = {
    password: RedisConfig.password,
    commandTimeout: RedisConfig.commandTimeout,
    ...extra,
  };
  const clusterNodes = (process.env.REDIS_CLUSTER_NODES || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)
    .map(s => {
      const [host, port] = s.split(':');
      return { host, port: Number(port) };
    });
  if (clusterNodes.length) {
    return new Redis.Cluster(clusterNodes, { redisOptions: common });
  }
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
