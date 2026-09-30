// 로컬 재현용 ChatService 대역.
// Prisma 엔진을 이 환경에서 받을 수 없어 DB 접근만 대체한다. 게이트웨이·Socket.IO·Redis 계층은 PAD 코드 그대로다.
// 서버 간에 공유돼야 하는 online_users 만 실제 MySQL(MariaDB) 테이블에 둔다.
import { Injectable } from '@nestjs/common';
import { createPool, Pool } from 'mysql2/promise';

@Injectable()
export class FakeChatService {
  private pool: Pool = createPool({ host: '127.0.0.1', user: 'pad', password: 'pad', database: 'pad', connectionLimit: 20 });
  private seq = 0;
  async addUserOnline(userId: number, clientId: string) {
    await this.pool.query('INSERT INTO online_users (user_id, client_id) VALUES (?, ?)', [userId, clientId]);
  }
  async deleteUserOnline(userId: number) {
    await this.pool.query('DELETE FROM online_users WHERE user_id = ?', [userId]);
  }
  async getSocketIds(ids: number[]) {
    const [rows] = await this.pool.query('SELECT client_id FROM online_users WHERE user_id IN (?)', [ids]);
    return (rows as any[]).map(r => r.client_id);
  }
  async getChannelId(u1: number, u2: number) { return 100000 + Math.min(u1, u2) * 1000 + Math.max(u1, u2); }
  async getAllChannels() { return []; }
  async getChannel(_u: number, channelId: number) { return { channel: { channelId } }; }
  async getLastMessageId() { return null; }
  async updateReadCount() {}
  async getChannelLastMessage() { return null; }
  async setLastMessageId() {}
  async createMessage(type: string, channelId: number, userId: number, content: string) {
    return { id: ++this.seq, content, read_count: 0 };
  }
  async getSenderProfile(userId: number) { return { userId, nickname: `u${userId}` }; }
  async getChannelOfflineUsers() { return []; }
  async handleChatNotices() {}
}
