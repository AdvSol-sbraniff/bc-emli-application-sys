import { Container, Flex } from '@chakra-ui/react';
import { ClipboardText, NotePencil, Tray } from '@phosphor-icons/react';
import React from 'react';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { HomeScreenBox } from './home-screen-box';

export const AdminHomeScreen = () => {
  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24">
      <BlueTitleBar title="AI Admin Portal" />
      <Container maxW="container.md" py={16}>
        <Flex direction="column" align="center" w="full">
          <Flex direction="column" align="center" w="full" gap={6}>
            <HomeScreenBox title="AI Invoices" description="" icon={<Tray size={24} />} href="/invoices-admin" />
            <HomeScreenBox
              title="AI Contractor Simulator"
              description=""
              icon={<NotePencil size={24} />}
              href="/submission-simulator-admin"
            />
            <HomeScreenBox
              title="Fields and Advice Editor"
              description=""
              icon={<ClipboardText size={24} />}
              href="/validation-rules-admin"
              h="full"
            />
          </Flex>
        </Flex>
      </Container>
    </Flex>
  );
};
