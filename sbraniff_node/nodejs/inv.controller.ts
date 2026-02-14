import { Controller, Post, Req, Body, BadRequestException, UsePipes, ValidationPipe } from '@nestjs/common';
import { IsOptional, IsString, IsUrl, IsObject, IsArray   } from 'class-validator';
import { Request, Response } from 'express';
import { InvService } from '../services/inv.service';


// start of Dtos

/**
 * Body: { sasUrl: string, modelId?: string }
 * Example curl:
 * curl -i -X POST "http://127.0.0.1:3001/inv/retry-ocr-with-sasurl" ^
 *   -H "Content-Type: application/json" ^
 *   -d "{\"sasUrl\":\"<SAS_URL>\",\"modelId\":\"prebuilt-invoice\"}"
 */
class RetryOcrWithSasUrlDto {
  @IsString()
  @IsUrl({ require_tld: false })
  sasUrl!: string;

  @IsOptional()
  @IsString()
  modelId?: string; // defaulted in controller
}

class GenAiDto {
  @IsArray()
  contextwindowjson!: any[];
}
// end of Dtos

// start of controller inv
@Controller('inv')
export class InvController {
  constructor(private readonly invService: InvService) {}

  @Post('HelloWorld')
  async HelloWorld(@Req() req: Request): Promise<{ message: string }> {
    return await this.invService.HelloWorld();
  }

  @Post('genaiHelloWorld')
  async genaiHelloWorld(): Promise<{ message: string }> {
    return await this.invService.genaiHelloWorld();
  }

  @Post('retry-ocr-with-sasurl')
  @UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
  async retryOcrWithSasUrl(@Body() dto: RetryOcrWithSasUrlDto) {

    const modelId = dto.modelId ?? 'prebuilt-invoice';
    return this.invService.retryOcrWithSasUrl(dto.sasUrl, modelId);
  }

@Post('genai')
@UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
async genai(@Body() dto: GenAiDto): Promise<any> {
  // returns a real JSON object to Ruby
  return this.invService.genai(dto.contextwindowjson);
}


// sample parsing checks
//    if (!dto.sasUrl.includes('blob.core.windows.net')) {
//      throw new BadRequestException('sasUrl must be an Azure Blob SAS URL.');
//    }


// END of controller 'inv'
}
