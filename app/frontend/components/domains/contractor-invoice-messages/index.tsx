import { Box, Container, Flex } from '@chakra-ui/react';
import React from 'react';
import { useParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { ContractorConversationPanel } from '../../shared/claims/contractor-conversation-panel';

export default function ContractorInvoiceMessagesScreen() {
  const { invoiceId } = useParams();

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Messages & Requested Changes" />
      <Container maxW="5xl" py={6}>
        <Box borderWidth="1px" borderRadius="lg" bg="white" p={5}>
          <ContractorConversationPanel invoiceId={invoiceId} messageListMaxHeight="520px" />
        </Box>
      </Container>
    </Flex>
  );
}
