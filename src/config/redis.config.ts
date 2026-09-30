import { Injectable } from '@nestjs/common';

// Redis 접속 정보는 환경 변수로만 받는다(비밀번호를 코드에 두지 않는다).
// REDIS_SENTINELS 가 있으면 Sentinel 모드, 없으면 단일 노드로 접속한다.
@Injectable()
export class RedisConfig {
  public static readonly host = process.env.REDIS_HOST || 'localhost';
  public static readonly port = parseInt(process.env.REDIS_PORT, 10) || 6379;
  public static readonly password = process.env.REDIS_PASSWORD || undefined;
  public static readonly sentinels = (process.env.REDIS_SENTINELS || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)
    .map(s => {
      const [host, port] = s.split(':');
      return { host, port: Number(port) };
    });
  public static readonly masterName =
    process.env.REDIS_MASTER_NAME || 'pad-master';
  // Sentinel 의 +switch-master 이벤트를 구독해 승격을 즉시 따라갈지
  public static readonly failoverDetector =
    process.env.REDIS_FAILOVER_DETECTOR === 'true';
  // 명령이 이 시간 안에 응답하지 않으면 실패로 처리(ms, 0 이면 끔)
  public static readonly commandTimeout =
    parseInt(process.env.REDIS_COMMAND_TIMEOUT_MS, 10) || undefined;
}
