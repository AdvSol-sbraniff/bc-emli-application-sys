import { Module, Global } from '@nestjs/common';
import { Pool } from 'pg';

import { InvController } from './controllers/inv.controller';
import { SimpleChatController } from './controllers/simple-chat.controller';
import { InvService } from './services/inv.service';
import { InvRepository } from './repositories/inv.repository';
import { SimpleChatService } from './services/simple-chat.service';

import { ConfigModule } from '@nestjs/config';

@Global()
@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true, // makes process.env available everywhere
    }),
  ],
  providers: [
    {
      provide: 'PG_POOL',
      useFactory: async (): Promise<Pool> => {
        return new Pool({
          host: 'localhost',
          port: 5432,
          user: 'invoice_app',
          password: 'app_pw',
          database: 'invoice_dev',
          max: 10,
        });
      },
    },
    InvService,
    InvRepository, // (optional but you imported it; include if you use it)
    SimpleChatService,
  ],
  controllers: [InvController, SimpleChatController],
  exports: ['PG_POOL'],
})
export class AppModule {}
