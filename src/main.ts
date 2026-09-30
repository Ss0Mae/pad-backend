import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from '@common/filters/http-exception.filter';
import { config } from 'dotenv';
import * as cookieParser from 'cookie-parser';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { RedisIoAdapter } from '@src/chat/redis-io.adapter';
config();

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.use(cookieParser());

  // 채팅 서버를 여러 대로 늘려도 메시지가 모든 서버의 소켓에 닿도록 Redis 어댑터 사용
  if (process.env.CHAT_REDIS_ADAPTER !== 'off') {
    const redisIoAdapter = new RedisIoAdapter(app);
    await redisIoAdapter.connectToRedis();
    app.useWebSocketAdapter(redisIoAdapter);
  }
  app.enableCors({
    origin: [
      'http://localhost:5173',
      'http://localhost:8080',
      'https://p-a-d.store',
    ],
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS', 'PUT'], // 💡 GET 포함
    credentials: true,
    allowedHeaders: ['Authorization', 'Content-Type'], // 💡 CORS 요청 헤더 허용
    exposedHeaders: ['Authorization'], // 💡 클라이언트에서 응답 헤더 사용 가능
  });

  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    })
  );

  const config = new DocumentBuilder()
    .setTitle('PAD API')
    .setDescription('PAD를 위한 REST API 문서입니다.')
    .setVersion('1.0')
    .addBearerAuth() // JWT 인증 추가
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api-docs', app, document, {
    swaggerOptions: {
      url: '/api-docs', // Swagger 문서 경로와 맞추기 위해 설정
    },
    customSiteTitle: 'API 문서',
  });

  //app.useGlobalFilters(new HttpExceptionFilter());
  await app.listen(process.env.PORT);
}
bootstrap();
