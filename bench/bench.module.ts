import { Module } from '@nestjs/common';
import { ChatGateway } from '@src/chat/chat.gateway';
import { ChatService } from '@src/chat/chat.service';
import { NotificationsService } from '@src/modules/notification/notification.service';
import { FakeChatService } from './fake-chat.service';
import { LegacyChatGateway } from './legacy-chat.gateway';

// CHAT_GATEWAY=legacy 면 어댑터 도입 전 게이트웨이(undefined.emit 재현용)를 띄운다.
const gateway = process.env.CHAT_GATEWAY === 'legacy' ? LegacyChatGateway : ChatGateway;

@Module({
  providers: [
    gateway,
    { provide: ChatService, useClass: FakeChatService },
    { provide: NotificationsService, useValue: {} },
  ],
})
export class BenchModule {}
