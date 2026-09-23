import {
  Body,
  Controller,
  Post,
  UsePipes,
  ValidationPipe,
} from '@nestjs/common';
import { IsOptional, IsString, MaxLength } from 'class-validator';
import { SimpleChatService } from '../services/simple-chat.service';

class SimpleChatDto {
  @IsString()
  prompt!: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  deployment_name?: string;
}

@Controller('inv')
export class SimpleChatController {
  constructor(private readonly simpleChatService: SimpleChatService) {}

  @Post('simple-chat')
  @UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
  async simpleChat(@Body() dto: SimpleChatDto): Promise<{ message: string }> {
    return this.simpleChatService.simpleChat(dto.prompt, dto.deployment_name);
  }
}
