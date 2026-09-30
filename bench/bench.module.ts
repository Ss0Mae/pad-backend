import { Module } from '@nestjs/common';
import { ChatGateway } from '@src/chat/chat.gateway';
import { ChatService } from '@src/chat/chat.service';
import { NotificationsService } from '@src/modules/notification/notification.service';
import { FakeChatService } from './fake-chat.service';

@Module({
  providers: [
    ChatGateway,
    { provide: ChatService, useClass: FakeChatService },
    { provide: NotificationsService, useValue: {} },
  ],
})
export class BenchModule {}
