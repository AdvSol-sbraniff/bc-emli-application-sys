import {
  Box,
  Button,
  Flex,
  Modal,
  ModalBody,
  ModalCloseButton,
  ModalContent,
  ModalHeader,
  ModalOverlay,
  Text,
} from '@chakra-ui/react';
import React from 'react';
import { getInvoiceUpgradeTypeMeta, InvoiceUpgradeTypeTile } from './invoice-upgrade-type-visual';

export const PossibleSupportingDocumentsButton = ({ onClick }: { onClick: () => void }) => (
  <Button size="lg" variant="secondary" fontSize="sm" onClick={onClick}>
    Possible Supporting Documents
  </Button>
);

const PossibleSupportingDocumentsContent = ({ groups }: { groups: any[] }) => {
  if (groups.length === 0) {
    return (
      <Text fontSize="md" opacity={0.7}>
        No supporting-document type mappings are configured for the detected upgrade types.
      </Text>
    );
  }

  return (
    <Box display="flex" flexDirection="column" gap="6px">
      {groups.map((group: any) => {
        const types = Array.isArray(group?.supporting_document_types) ? group.supporting_document_types : [];
        const title = String(
          group?.upgrade_type_description ||
            getInvoiceUpgradeTypeMeta(String(group?.upgrade_type_key || 'common')).label,
        );

        return (
          <Box
            key={String(group?.invoice_upgrade_type_id || group?.upgrade_type_key || 'group')}
            borderRadius="md"
            px="10px"
            py="2px"
          >
            <Flex align="center" gap="8px" mb="2px" wrap="wrap">
              <Text fontSize="md" fontWeight="bold" noOfLines={1}>
                {title}
              </Text>
              <InvoiceUpgradeTypeTile
                upgradeTypeKey={String(group?.upgrade_type_key || 'common')}
                description={group?.upgrade_type_description}
                size={24}
              />
            </Flex>

            {types.length === 0 ? (
              <Text fontSize="md" opacity={0.7}>
                No supporting document types mapped to this upgrade type.
              </Text>
            ) : (
              <Box pl="12px">
                {types.map((typeRow: any) => (
                  <Text key={String(typeRow?.supporting_document_type_id || typeRow?.type_key || 'type')} fontSize="md">
                    {String(typeRow?.description || typeRow?.type_key || 'Unknown type')}
                  </Text>
                ))}
              </Box>
            )}
          </Box>
        );
      })}
    </Box>
  );
};

export const PossibleSupportingDocumentsModal = ({
  isOpen,
  onClose,
  groups,
}: {
  isOpen: boolean;
  onClose: () => void;
  groups: any[];
}) => (
  <Modal isOpen={isOpen} onClose={onClose} size="2xl" isCentered>
    <ModalOverlay bg="rgba(15, 23, 42, 0.34)" backdropFilter="blur(8px)" />
    <ModalContent
      mx={4}
      borderRadius="xl"
      boxShadow="0 28px 90px rgba(15, 23, 42, 0.28)"
      maxH="calc(100vh - 48px)"
      overflowY="auto"
    >
      <ModalHeader>Possible Supporting Documents</ModalHeader>
      <ModalCloseButton />
      <ModalBody pb={6}>
        <PossibleSupportingDocumentsContent groups={groups} />
        <Flex justify="flex-end" mt={6}>
          <Button variant="primary" onClick={onClose}>
            Close
          </Button>
        </Flex>
      </ModalBody>
    </ModalContent>
  </Modal>
);
