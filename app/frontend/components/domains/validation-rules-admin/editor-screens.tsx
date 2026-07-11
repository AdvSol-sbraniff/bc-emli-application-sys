import React from 'react';
import {
  Box,
  Button,
  Checkbox,
  FormControl,
  FormLabel,
  Grid,
  GridItem,
  HStack,
  Input,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Text,
  Textarea,
  VStack,
} from '@chakra-ui/react';

export type MappingEditorRow = {
  invoice_upgrade_type_id: string;
  label: string;
  checked: boolean;
};

type SharedProps = {
  recordKey: string;
  enabled: boolean;
  mappings: MappingEditorRow[];
  selectedUpgradeTypeId: string;
  onEnabledChange: (next: boolean) => void;
  onRecordKeyChange: (next: string) => void;
  onMappingCheckedChange: (invoiceUpgradeTypeId: string, checked: boolean) => void;
  onCancel: () => void;
  onSave: () => void;
  saving: boolean;
};

type CodeRuleEditorProps = SharedProps & {
  description: string;
  sourceQuote: string;
  contractorVisibleFlag: boolean;
  passAdminMessage: string;
  warnAdminMessage: string;
  failAdminMessage: string;
  infoAdminMessage: string;
  adminNotes: string;
  onDescriptionChange: (next: string) => void;
  onSourceQuoteChange: (next: string) => void;
  onContractorVisibleFlagChange: (next: boolean) => void;
  onPassAdminMessageChange: (next: string) => void;
  onWarnAdminMessageChange: (next: string) => void;
  onFailAdminMessageChange: (next: string) => void;
  onInfoAdminMessageChange: (next: string) => void;
  onAdminNotesChange: (next: string) => void;
};

type CodeLocatedFieldEditorProps = SharedProps & {
  description: string;
  onDescriptionChange: (next: string) => void;
};

type GenaiEditorProps = SharedProps & {
  promptText: string;
  onPromptTextChange: (next: string) => void;
};

type GenaiRuleEditorProps = GenaiEditorProps & {
  sourceQuote: string;
  contractorVisibleFlag: boolean;
  onSourceQuoteChange: (next: string) => void;
  onContractorVisibleFlagChange: (next: boolean) => void;
};

function MappingSection({
  mappings,
  selectedUpgradeTypeId,
  onMappingCheckedChange,
}: {
  mappings: MappingEditorRow[];
  selectedUpgradeTypeId: string;
  onMappingCheckedChange: (invoiceUpgradeTypeId: string, checked: boolean) => void;
}) {
  return (
    <Box borderWidth="1px" borderRadius="md" p={4}>
      <Text fontWeight="bold" mb={1}>
        Upgrade type mappings
      </Text>
      <Text fontSize="sm" opacity={0.75} mb={4}>
        Check the upgrade types that should use this record. The current taxonomy is highlighted so shared usage stays
        visible without exposing ordering.
      </Text>

      <Grid templateColumns="repeat(2, minmax(0, 1fr))" gap={3}>
        {mappings.map((mapping) => (
          <GridItem key={mapping.invoice_upgrade_type_id}>
            <Box
              borderWidth="1px"
              borderRadius="md"
              p={3}
              h="100%"
              bg={mapping.invoice_upgrade_type_id === selectedUpgradeTypeId ? 'blue.50' : 'white'}
            >
              <Checkbox
                isChecked={mapping.checked}
                onChange={(e) => onMappingCheckedChange(mapping.invoice_upgrade_type_id, e.target.checked)}
              >
                {mapping.label}
              </Checkbox>
            </Box>
          </GridItem>
        ))}
      </Grid>
    </Box>
  );
}

function EditorFooter({ onCancel, onSave, saving }: { onCancel: () => void; onSave: () => void; saving: boolean }) {
  return (
    <HStack spacing={3} justify="end">
      <Button variant="ghost" onClick={onCancel}>
        Cancel
      </Button>
      <Button colorScheme="blue" onClick={onSave} isLoading={saving}>
        Save
      </Button>
    </HStack>
  );
}

function SharedTopFields({
  recordKey,
  enabled,
  onEnabledChange,
  onRecordKeyChange,
}: {
  recordKey: string;
  enabled: boolean;
  onEnabledChange: (next: boolean) => void;
  onRecordKeyChange: (next: string) => void;
}) {
  return (
    <>
      <FormControl pt={1}>
        <Checkbox isChecked={enabled} onChange={(e) => onEnabledChange(e.target.checked)}>
          Enabled
        </Checkbox>
      </FormControl>

      <FormControl isRequired>
        <FormLabel>Key</FormLabel>
        <Input value={recordKey} onChange={(e) => onRecordKeyChange(e.target.value)} />
      </FormControl>
    </>
  );
}

function RuleSourceFields({
  sourceQuote,
  contractorVisibleFlag,
  onSourceQuoteChange,
  onContractorVisibleFlagChange,
}: {
  sourceQuote: string;
  contractorVisibleFlag: boolean;
  onSourceQuoteChange: (next: string) => void;
  onContractorVisibleFlagChange: (next: boolean) => void;
}) {
  return (
    <>
      <FormControl isRequired>
        <FormLabel>Source quote from requirement PDF</FormLabel>
        <Textarea value={sourceQuote} onChange={(e) => onSourceQuoteChange(e.target.value)} minH="110px" />
      </FormControl>

      <FormControl>
        <Checkbox isChecked={contractorVisibleFlag} onChange={(e) => onContractorVisibleFlagChange(e.target.checked)}>
          Visible to contractor advice
        </Checkbox>
      </FormControl>
    </>
  );
}

export function CodeRuleEditorScreen(props: CodeRuleEditorProps) {
  return (
    <VStack align="stretch" spacing={5}>
      <Tabs variant="enclosed" isLazy>
        <TabList>
          <Tab>Details</Tab>
          <Tab>Admin Messages</Tab>
          <Tab>Upgrade Type Mappings</Tab>
        </TabList>

        <TabPanels>
          <TabPanel px={0} pt={5}>
            <VStack align="stretch" spacing={5}>
              <SharedTopFields
                recordKey={props.recordKey}
                enabled={props.enabled}
                onEnabledChange={props.onEnabledChange}
                onRecordKeyChange={props.onRecordKeyChange}
              />

              <FormControl isRequired>
                <FormLabel>Description</FormLabel>
                <Textarea
                  value={props.description}
                  onChange={(e) => props.onDescriptionChange(e.target.value)}
                  minH="120px"
                />
              </FormControl>

              <RuleSourceFields
                sourceQuote={props.sourceQuote}
                contractorVisibleFlag={props.contractorVisibleFlag}
                onSourceQuoteChange={props.onSourceQuoteChange}
                onContractorVisibleFlagChange={props.onContractorVisibleFlagChange}
              />
            </VStack>
          </TabPanel>

          <TabPanel px={0} pt={5}>
            <VStack align="stretch" spacing={4}>
              <FormControl>
                <FormLabel>Pass admin message</FormLabel>
                <Textarea
                  value={props.passAdminMessage}
                  onChange={(e) => props.onPassAdminMessageChange(e.target.value)}
                />
              </FormControl>
              <FormControl>
                <FormLabel>Warn admin message</FormLabel>
                <Textarea
                  value={props.warnAdminMessage}
                  onChange={(e) => props.onWarnAdminMessageChange(e.target.value)}
                />
              </FormControl>
              <FormControl>
                <FormLabel>Fail admin message</FormLabel>
                <Textarea
                  value={props.failAdminMessage}
                  onChange={(e) => props.onFailAdminMessageChange(e.target.value)}
                />
              </FormControl>
              <FormControl>
                <FormLabel>Info admin message</FormLabel>
                <Textarea
                  value={props.infoAdminMessage}
                  onChange={(e) => props.onInfoAdminMessageChange(e.target.value)}
                />
              </FormControl>
              <FormControl>
                <FormLabel>Admin notes</FormLabel>
                <Textarea value={props.adminNotes} onChange={(e) => props.onAdminNotesChange(e.target.value)} />
              </FormControl>
            </VStack>
          </TabPanel>

          <TabPanel px={0} pt={5}>
            <MappingSection
              mappings={props.mappings}
              selectedUpgradeTypeId={props.selectedUpgradeTypeId}
              onMappingCheckedChange={props.onMappingCheckedChange}
            />
          </TabPanel>
        </TabPanels>
      </Tabs>

      <EditorFooter onCancel={props.onCancel} onSave={props.onSave} saving={props.saving} />
    </VStack>
  );
}

export function CodeLocatedFieldEditorScreen(props: CodeLocatedFieldEditorProps) {
  return (
    <VStack align="stretch" spacing={5}>
      <SharedTopFields
        recordKey={props.recordKey}
        enabled={props.enabled}
        onEnabledChange={props.onEnabledChange}
        onRecordKeyChange={props.onRecordKeyChange}
      />

      <FormControl isRequired>
        <FormLabel>Description</FormLabel>
        <Textarea value={props.description} onChange={(e) => props.onDescriptionChange(e.target.value)} minH="120px" />
      </FormControl>

      <Box borderWidth="1px" borderRadius="md" p={4} bg="gray.50">
        <Text fontWeight="bold">Global code field</Text>
        <Text fontSize="sm" opacity={0.75}>
          Code-located DB facts are not upgrade-type-specific in this first chunk.
        </Text>
      </Box>

      <EditorFooter onCancel={props.onCancel} onSave={props.onSave} saving={props.saving} />
    </VStack>
  );
}

export function GenaiRuleEditorScreen(props: GenaiRuleEditorProps) {
  return (
    <VStack align="stretch" spacing={5}>
      <Tabs variant="enclosed" isLazy>
        <TabList>
          <Tab>Details</Tab>
          <Tab>Upgrade Type Mappings</Tab>
        </TabList>

        <TabPanels>
          <TabPanel px={0} pt={5}>
            <VStack align="stretch" spacing={5}>
              <SharedTopFields
                recordKey={props.recordKey}
                enabled={props.enabled}
                onEnabledChange={props.onEnabledChange}
                onRecordKeyChange={props.onRecordKeyChange}
              />

              <FormControl isRequired>
                <FormLabel>Prompt text</FormLabel>
                <Textarea
                  value={props.promptText}
                  onChange={(e) => props.onPromptTextChange(e.target.value)}
                  minH="180px"
                />
              </FormControl>

              <RuleSourceFields
                sourceQuote={props.sourceQuote}
                contractorVisibleFlag={props.contractorVisibleFlag}
                onSourceQuoteChange={props.onSourceQuoteChange}
                onContractorVisibleFlagChange={props.onContractorVisibleFlagChange}
              />
            </VStack>
          </TabPanel>

          <TabPanel px={0} pt={5}>
            <MappingSection
              mappings={props.mappings}
              selectedUpgradeTypeId={props.selectedUpgradeTypeId}
              onMappingCheckedChange={props.onMappingCheckedChange}
            />
          </TabPanel>
        </TabPanels>
      </Tabs>

      <EditorFooter onCancel={props.onCancel} onSave={props.onSave} saving={props.saving} />
    </VStack>
  );
}

export function GenaiLocatedFieldEditorScreen(props: GenaiEditorProps) {
  return (
    <VStack align="stretch" spacing={5}>
      <Tabs variant="enclosed" isLazy>
        <TabList>
          <Tab>Details</Tab>
          <Tab>Upgrade Type Mappings</Tab>
        </TabList>

        <TabPanels>
          <TabPanel px={0} pt={5}>
            <VStack align="stretch" spacing={5}>
              <SharedTopFields
                recordKey={props.recordKey}
                enabled={props.enabled}
                onEnabledChange={props.onEnabledChange}
                onRecordKeyChange={props.onRecordKeyChange}
              />

              <FormControl isRequired>
                <FormLabel>Prompt text</FormLabel>
                <Textarea
                  value={props.promptText}
                  onChange={(e) => props.onPromptTextChange(e.target.value)}
                  minH="180px"
                />
              </FormControl>
            </VStack>
          </TabPanel>

          <TabPanel px={0} pt={5}>
            <MappingSection
              mappings={props.mappings}
              selectedUpgradeTypeId={props.selectedUpgradeTypeId}
              onMappingCheckedChange={props.onMappingCheckedChange}
            />
          </TabPanel>
        </TabPanels>
      </Tabs>

      <EditorFooter onCancel={props.onCancel} onSave={props.onSave} saving={props.saving} />
    </VStack>
  );
}
