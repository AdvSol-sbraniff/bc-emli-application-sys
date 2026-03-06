import { Controller, Post, Req, Body, BadRequestException, UsePipes, ValidationPipe } from '@nestjs/common';
import { IsOptional, IsString, IsUrl, IsObject, IsArray,  IsInt, Min   } from 'class-validator';
import { Request, Response } from 'express';
import { InvService } from '../services/inv.service';

import { UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Type } from 'class-transformer';


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

class MintSasDto {
  @IsString()
  storageKey!: string;

  @IsOptional()
  @IsString()
  container?: string;
}


class UploadPdfDto {
  // sessions/<session_uuid>/pdfs/<invoice_version_uuid>/original.PDF
  @IsString()
  sessionId!: string;

  @IsString()
  invoiceVersionId!: string;

  @IsOptional()
  @IsString()
  container?: string;

  @IsOptional()
  @IsString()
  filename?: string; // default original.PDF
}


class OcrByBlobDto {
  @IsString()
  storageKey!: string;

  @IsOptional()
  @IsString()
  container?: string;

  @IsOptional()
  @IsString()
  modelId?: string; // default prebuilt-invoice
}

// end of Dtos

// start of controller inv
@Controller('inv')
export class InvController {
  constructor(private readonly invService: InvService) {}

  @Post('mint-sas')
@UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
async mintSas(@Body() dto: MintSasDto): Promise<any> {
  return this.invService.mintSasUrl({
    container: dto.container,
    storageKey: dto.storageKey,
  });
}

  // for test only
  @Post('HelloWorld')
  async HelloWorld(@Req() req: Request): Promise<{ message: string }> {
    return await this.invService.HelloWorld();
  }

  // for test only
    @Post('genaiHelloWorld')
  async genaiHelloWorld(): Promise<{ message: string }> {
    return await this.invService.genaiHelloWorld();
  }


// ============================================================
// SECTION 20 — Controller: POST /inv/ocr
// ============================================================
@Post('ocr')
@UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
async ocr(@Body() dto: OcrByBlobDto): Promise<any> {
  const modelId = dto.modelId ?? 'prebuilt-invoice';
  return this.invService.ocrByBlob({
    container: dto.container,
    storageKey: dto.storageKey,
    modelId,
  });
}

@Post('genai')
@UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
async genai(@Body() dto: GenAiDto): Promise<any> {
  // returns a real JSON object to Ruby
  return this.invService.genai(dto.contextwindowjson);
}

@Post('upload-pdf')
@UseInterceptors(FileInterceptor('file'))
@UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
async uploadPdf(
  @UploadedFile() file: Express.Multer.File,
  @Body() dto: UploadPdfDto,
) {
  if (!file) {
    throw new BadRequestException("Missing multipart file field 'file'.");
  }

return this.invService.uploadPdfToBlob({
  sessionId: dto.sessionId,
  invoiceVersionId: dto.invoiceVersionId,
  container: dto.container,
  filename: dto.filename,
  buffer: file.buffer,
  contentType: file.mimetype || 'application/pdf',
  originalName: file.originalname,
});

}



// sample parsing checks
//    if (!dto.sasUrl.includes('blob.core.windows.net')) {
//      throw new BadRequestException('sasUrl must be an Azure Blob SAS URL.');
//    }


// END of controller 'inv'
}
