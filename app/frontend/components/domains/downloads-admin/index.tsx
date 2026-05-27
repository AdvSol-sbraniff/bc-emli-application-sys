import React from 'react';
import { Box, Button, Container, Flex, Text } from '@chakra-ui/react';
import { ArrowSquareOut } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type DownloadTool = {
  title: string;
  description: string;
  path: string;
};

const downloadTools: DownloadTool[] = [
  {
    title: 'AHRI heat pump product list config',
    description:
      'Download, import, and inspect the BC Hydro heat pump product lists used by AHRI and heat-pump code rules.',
    path: '/heat-pump-product-list-admin',
  },
  {
    title: 'NEEA HPWH product list config',
    description:
      'Download, import, and inspect the NEEA heat pump water heater qualified products list used by HPWH code rules.',
    path: '/hpwh-product-list-admin',
  },
];

export default function DownloadsAdminScreen() {
  const openTool = (path: string) => {
    window.open(path, '_blank', 'noopener,noreferrer');
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Downloads" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Text fontSize="lg" fontWeight="bold" mb={1}>
            External reference downloads
          </Text>
          <Text fontSize="sm" opacity={0.75} maxW="760px" mb={5}>
            This page collects admin tools that download or refresh external reference data used by code-owned checks.
            More download tools can be added here as new reference sources are automated.
          </Text>

          <Flex gap={4} wrap="wrap">
            {downloadTools.map((tool) => (
              <Box
                key={tool.path}
                borderWidth="1px"
                borderColor="greys.grey20"
                borderRadius="lg"
                p={4}
                bg="gray.50"
                w={{ base: 'full', md: '420px' }}
              >
                <Text fontWeight="bold" mb={1}>
                  {tool.title}
                </Text>
                <Text fontSize="sm" opacity={0.75} mb={4}>
                  {tool.description}
                </Text>
                <Button
                  size="sm"
                  colorScheme="blue"
                  rightIcon={<ArrowSquareOut size={16} />}
                  onClick={() => openTool(tool.path)}
                >
                  Open
                </Button>
              </Box>
            ))}
          </Flex>
        </Box>
      </Container>
    </Flex>
  );
}
