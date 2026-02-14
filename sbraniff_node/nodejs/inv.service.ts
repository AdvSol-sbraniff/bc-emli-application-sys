
// 2023 standard - old
// import { AzureKeyCredential, DocumentAnalysisClient } from '@azure/ai-form-recognizer';

import { Injectable } from '@nestjs/common';
import DocumentIntelligence, {
  getLongRunningPoller,
  isUnexpected,
} from "@azure-rest/ai-document-intelligence";
import { AzureKeyCredential } from "@azure/core-auth";
import OpenAI from "openai";


@Injectable()
export class InvService {

//the constructor reserved def for build ONCE on nest load
  private readonly client: ReturnType<typeof DocumentIntelligence>;

  private readonly genaiClient: OpenAI;
  private readonly genaiDeployment: string;

  constructor() {
    const endpoint = process.env.DOCINTEL_ENDPOINT;
    const key = process.env.DOCINTEL_KEY;

    if (!endpoint || !key) {
      throw new Error("Missing DOCINTEL_ENDPOINT or DOCINTEL_KEY");
    }

    // REST-style client (latest standard)
    // Note: the library defaults to apiVersion 2024-11-30, so you usually don't need to set it. :contentReference[oaicite:3]{index=3}
    this.client = DocumentIntelligence(endpoint, new AzureKeyCredential(key));

    // ---- GenAI (OpenAI SDK, Responses API) ----
    const genaiBaseUrl = process.env.GENAI_BASE_URL;
    const genaiKey = process.env.GENAI_KEY;
    const genaiDeployment = process.env.GENAI_DEPLOYMENT;

    if (!genaiBaseUrl || !genaiKey || !genaiDeployment) {
      throw new Error("Missing GENAI_BASE_URL and/or GENAI_KEY and/or GENAI_DEPLOYMENT");
    }

    this.genaiDeployment = genaiDeployment;

    // build once at Nest load
    this.genaiClient = new OpenAI({
      apiKey: genaiKey,
      baseURL: genaiBaseUrl,
    });

  }

  async retryOcrWithSasUrl(sasUrl: string, modelId: string = "prebuilt-invoice") {
    // Start analyze from URL (SAS URL is perfect for this)
    const initialResponse = await this.client
      .path("/documentModels/{modelId}:analyze", modelId)
      .post({
        body: { urlSource: sasUrl },
        contentType: "application/json",
      });

    if (isUnexpected(initialResponse)) {
      // initialResponse.body usually contains the service error payload
      throw new Error(`Document Intelligence error: ${JSON.stringify(initialResponse.body)}`);
    }

    // Poll until done
    const poller = getLongRunningPoller(this.client, initialResponse);
    const finalResponse = await poller.pollUntilDone();

    // The finalResponse.body typically contains the analyze result payload
    const result = (finalResponse as any)?.body?.analyzeResult ?? (finalResponse as any)?.body;
    console.log("[DI] analyze complete. modelId:", modelId);

    // Minimal “documents[0].fields” equivalent (same concept as your old code)
    const recDocuments0 = (result as any)?.documents?.[0];
    if (!recDocuments0) {
      console.log("No documents[0] found");
      return result;
    }

    const recFields = recDocuments0.fields as any;
    if (!recFields) {
      console.log("No fields found");
      return result;
    }

   const canonical_hdr = {
     di_ocr_invoice_id: recFields?.["InvoiceId"]?.valueString ?? recFields?.["InvoiceId"]?.content ?? null,
     di_ocr_invoice_date: recFields?.["InvoiceDate"]?.valueDate ?? recFields?.["InvoiceDate"]?.content ?? null,
     di_ocr_vendor_name: recFields?.["VendorName"]?.valueString ?? recFields?.["VendorName"]?.content ?? null,
     di_ocr_vendor_address: recFields?.["VendorAddress"]?.valueString ?? recFields?.["VendorAddress"]?.content ?? null,
     di_ocr_customer_name: recFields?.["CustomerName"]?.valueString ?? recFields?.["CustomerName"]?.content ?? null,
     di_ocr_billing_address: recFields?.["BillingAddress"]?.valueString ?? recFields?.["BillingAddress"]?.content ?? null,
     di_ocr_sub_total: recFields?.["SubTotal"]?.valueCurrency?.amount ?? recFields?.["SubTotal"]?.valueNumber ?? null,
     di_ocr_total_tax: recFields?.["TotalTax"]?.valueCurrency?.amount ?? recFields?.["TotalTax"]?.valueNumber ?? null,
     di_ocr_invoice_total: recFields?.["InvoiceTotal"]?.valueCurrency?.amount ?? recFields?.["InvoiceTotal"]?.valueNumber ?? null,
     di_ocr_amount_due: recFields?.["AmountDue"]?.valueCurrency?.amount ?? recFields?.["AmountDue"]?.valueNumber ?? null,
   };
   console.log("[DI] canonical header:", canonical_hdr);


const items = recFields?.["Items"]?.valueArray;
if (!items?.length) {
  console.log("[DI] No Items found");
} else {
  for (let i = 0; i < items.length; i++) {
    const obj = items[i]?.valueObject;
    if (!obj) continue;

    const description =
      obj?.["Description"]?.valueString ?? obj?.["Description"]?.content ?? null;

    const quantity =
      obj?.["Quantity"]?.valueNumber ?? (obj?.["Quantity"]?.content ? Number(obj["Quantity"].content) : null);

    const unitPrice =
      obj?.["UnitPrice"]?.valueCurrency?.amount ?? obj?.["UnitPrice"]?.valueNumber ?? null;

    const amount =
      obj?.["Amount"]?.valueCurrency?.amount ?? obj?.["Amount"]?.valueNumber ?? null;

    console.log(`[DI] Item ${i + 1}:`, { description, quantity, unitPrice, amount });
  }
}

    console.log("service.retryOcrWithSasUrl: exiting");
    return result; // BIG JSON


  }
  
  
  // start HelloWorld
  async HelloWorld(): Promise<{ message: string }> {
    console.log("service.HelloWorld: exiting");
    return { message: 'hello from InvService' };
  }


// called from curl for troubleshooting
async genaiHelloWorld(): Promise<{ message: string }> {
  const arrConversation: any[] = [];

  const recConversationSystem = {
    role: "system",
    content: [{ type: "input_text", text: "You are a helpful assistant. Keep it short." }],
  };
  arrConversation.push(recConversationSystem);

  const recConversationUser = {
    role: "user",
    content: [{ type: "input_text", text: "Say hello to Stephen." }],
  };
  arrConversation.push(recConversationUser);

  const resp = await this.genaiClient.responses.create({
    model: this.genaiDeployment,
    input: arrConversation,
  });
  console.log("genaiDeployment was", this.genaiDeployment);
  console.log("service.genaiHelloWorld: exiting");
  return { message: resp.output_text };
}

// Rails sends the context window JSON; we pass it through.
// We return parsed JSON from the model.
async genai(contextwindowjson: any): Promise<any> {
  const resp = await this.genaiClient.responses.create({
    model: this.genaiDeployment,
    input: contextwindowjson, // pass-through
  });

  // Model returns JSON text (because you told it to)
  const raw = (resp.output_text ?? '').trim();
  return JSON.parse(raw); // controller will return this as JSON
}





// end service layer class
}



