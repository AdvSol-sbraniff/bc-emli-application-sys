import React from 'react';
import { Box, Container, Flex } from '@chakra-ui/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { AdminConversationPanel } from '../../shared/claims/admin-invoice-communication-panels';

const getParam = (search: string, key: string) => new URLSearchParams(search).get(key) ?? '';

export default function ConversationMessagesAdminScreen() {
  const location = useLocation();
  const invoiceId = getParam(location.search, 'invoice_id');
  const contractorBusinessName = getParam(location.search, 'context_contractor_business_name');
  const diOcrInvoiceId = getParam(location.search, 'context_di_ocr_invoice_id');
  const latestInvoiceVersionId = getParam(location.search, 'latest_invoice_version_id');

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Contractor Conversation" />
      <Container maxW="6xl" px={6} pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="gray.200" borderRadius="xl" overflow="hidden" bg="white">
          <AdminConversationPanel
            invoiceId={invoiceId}
            latestInvoiceVersionId={latestInvoiceVersionId}
            contractorBusinessName={contractorBusinessName}
            diOcrInvoiceId={diOcrInvoiceId}
          />
        </Box>
      </Container>
    </Flex>
  );
}
