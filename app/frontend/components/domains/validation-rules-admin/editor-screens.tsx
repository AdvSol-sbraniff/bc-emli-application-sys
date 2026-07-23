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
  Select,
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
  recordKeyReadOnly: boolean;
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
  contractorDisplayName: string;
  description: string;
  sourceQuote: string;
  contractorAction: string;
  contractorVisibility: string;
  contractorBlockingPolicy: string;
  adminWorkflowPolicy: string;
  passAdminMessage: string;
  warnAdminMessage: string;
  failAdminMessage: string;
  infoAdminMessage: string;
  adminNotes: string;
  onContractorDisplayNameChange: (next: string) => void;
  onDescriptionChange: (next: string) => void;
  onSourceQuoteChange: (next: string) => void;
  onContractorActionChange: (next: string) => void;
  onContractorVisibilityChange: (next: string) => void;
  onContractorBlockingPolicyChange: (next: string) => void;
  onAdminWorkflowPolicyChange: (next: string) => void;
  onPassAdminMessageChange: (next: string) => void;
  onWarnAdminMessageChange: (next: string) => void;
  onFailAdminMessageChange: (next: string) => void;
  onInfoAdminMessageChange: (next: string) => void;
  onAdminNotesChange: (next: string) => void;
};

type CodeLocatedFieldEditorProps = SharedProps & {
  contractorDisplayName: string;
  description: string;
  onContractorDisplayNameChange: (next: string) => void;
  onDescriptionChange: (next: string) => void;
};

type GenaiEditorProps = SharedProps & {
  contractorDisplayName: string;
  promptText: string;
  onContractorDisplayNameChange: (next: string) => void;
  onPromptTextChange: (next: string) => void;
};

type GenaiRuleEditorProps = GenaiEditorProps & {
  sourceQuote: string;
  contractorAction: string;
  contractorVisibility: string;
  contractorBlockingPolicy: string;
  adminWorkflowPolicy: string;
  onSourceQuoteChange: (next: string) => void;
  onContractorActionChange: (next: string) => void;
  onContractorVisibilityChange: (next: string) => void;
  onContractorBlockingPolicyChange: (next: string) => void;
  onAdminWorkflowPolicyChange: (next: string) => void;
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
  recordKeyReadOnly,
  enabled,
  onEnabledChange,
  onRecordKeyChange,
}: {
  recordKey: string;
  recordKeyReadOnly: boolean;
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
        <Input
          value={recordKey}
          onChange={(e) => onRecordKeyChange(e.target.value)}
          isReadOnly={recordKeyReadOnly}
          bg={recordKeyReadOnly ? 'gray.100' : undefined}
        />
        {recordKeyReadOnly ? (
          <Text fontSize="xs" opacity={0.7} mt={1}>
            Keys are permanent after creation because workflow history uses them as durable identities.
          </Text>
        ) : null}
      </FormControl>
    </>
  );
}

function RuleSourceFields({
  sourceQuote,
  contractorAction,
  contractorVisibility,
  contractorBlockingPolicy,
  adminWorkflowPolicy,
  onSourceQuoteChange,
  onContractorActionChange,
  onContractorVisibilityChange,
  onContractorBlockingPolicyChange,
  onAdminWorkflowPolicyChange,
}: {
  sourceQuote: string;
  contractorAction: string;
  contractorVisibility: string;
  contractorBlockingPolicy: string;
  adminWorkflowPolicy: string;
  onSourceQuoteChange: (next: string) => void;
  onContractorActionChange: (next: string) => void;
  onContractorVisibilityChange: (next: string) => void;
  onContractorBlockingPolicyChange: (next: string) => void;
  onAdminWorkflowPolicyChange: (next: string) => void;
}) {
  return (
    <>
      <FormControl isRequired>
        <FormLabel>Source quote from requirement PDF</FormLabel>
        <Textarea value={sourceQuote} onChange={(e) => onSourceQuoteChange(e.target.value)} minH="110px" />
      </FormControl>

      <FormControl>
        <FormLabel>Pre-check contractor action</FormLabel>
        <Textarea value={contractorAction} onChange={(e) => onContractorActionChange(e.target.value)} minH="90px" />
        <Text fontSize="xs" opacity={0.7} mt={1}>
          Shown during contractor pre-check. Once an administrator opens a revision, the human-authored request becomes
          the action instead.
        </Text>
      </FormControl>

      <Grid templateColumns={{ base: '1fr', xl: 'repeat(3, minmax(0, 1fr))' }} gap={4}>
        <FormControl>
          <FormLabel>Contractor visibility</FormLabel>
          <Select
            value={contractorVisibility}
            onChange={(e) => {
              const next = e.target.value;
              onContractorVisibilityChange(next);
              if (next === 'hidden') onContractorBlockingPolicyChange('non_blocking');
            }}
          >
            <option value="hidden">Hidden / non-impacting</option>
            <option value="fail_only">Visible for errors only</option>
            <option value="warn_and_fail">Visible for warnings and errors</option>
          </Select>
          <Text fontSize="xs" opacity={0.7} mt={1}>
            Controls when this rule appears in contractor advice and submission review.
          </Text>
        </FormControl>

        <FormControl>
          <FormLabel>Submission blocking</FormLabel>
          <Select
            value={contractorBlockingPolicy}
            onChange={(e) => onContractorBlockingPolicyChange(e.target.value)}
            isDisabled={contractorVisibility === 'hidden'}
          >
            <option value="non_blocking">Does not block submission</option>
            <option value="block_on_fail">Blocks submission on error</option>
          </Select>
          <Text fontSize="xs" opacity={0.7} mt={1}>
            Warnings never block. A blocking error must be corrected before submission.
          </Text>
        </FormControl>

        <FormControl>
          <FormLabel>Admin workflow management</FormLabel>
          <Select value={adminWorkflowPolicy} onChange={(e) => onAdminWorkflowPolicyChange(e.target.value)}>
            <option value="not_managed">Not workflow-managed</option>
            <option value="fail_only">Workflow-managed for errors only</option>
            <option value="warn_and_fail">Workflow-managed for warnings and errors</option>
            <option value="all_results">Workflow-managed for all results</option>
          </Select>
          <Text fontSize="xs" opacity={0.7} mt={1}>
            Controls which results require an admin review decision before sending a revision or approving.
          </Text>
        </FormControl>
      </Grid>
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
                recordKeyReadOnly={props.recordKeyReadOnly}
                enabled={props.enabled}
                onEnabledChange={props.onEnabledChange}
                onRecordKeyChange={props.onRecordKeyChange}
              />

              <FormControl isRequired>
                <FormLabel>Contractor-friendly name</FormLabel>
                <Input
                  value={props.contractorDisplayName}
                  onChange={(e) => props.onContractorDisplayNameChange(e.target.value)}
                />
              </FormControl>

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
                contractorAction={props.contractorAction}
                contractorVisibility={props.contractorVisibility}
                contractorBlockingPolicy={props.contractorBlockingPolicy}
                adminWorkflowPolicy={props.adminWorkflowPolicy}
                onSourceQuoteChange={props.onSourceQuoteChange}
                onContractorActionChange={props.onContractorActionChange}
                onContractorVisibilityChange={props.onContractorVisibilityChange}
                onContractorBlockingPolicyChange={props.onContractorBlockingPolicyChange}
                onAdminWorkflowPolicyChange={props.onAdminWorkflowPolicyChange}
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
        recordKeyReadOnly={props.recordKeyReadOnly}
        enabled={props.enabled}
        onEnabledChange={props.onEnabledChange}
        onRecordKeyChange={props.onRecordKeyChange}
      />

      <FormControl isRequired>
        <FormLabel>Contractor-friendly name</FormLabel>
        <Input
          value={props.contractorDisplayName}
          onChange={(e) => props.onContractorDisplayNameChange(e.target.value)}
        />
      </FormControl>

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
                recordKeyReadOnly={props.recordKeyReadOnly}
                enabled={props.enabled}
                onEnabledChange={props.onEnabledChange}
                onRecordKeyChange={props.onRecordKeyChange}
              />

              <FormControl isRequired>
                <FormLabel>Contractor-friendly name</FormLabel>
                <Input
                  value={props.contractorDisplayName}
                  onChange={(e) => props.onContractorDisplayNameChange(e.target.value)}
                />
              </FormControl>

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
                contractorAction={props.contractorAction}
                contractorVisibility={props.contractorVisibility}
                contractorBlockingPolicy={props.contractorBlockingPolicy}
                adminWorkflowPolicy={props.adminWorkflowPolicy}
                onSourceQuoteChange={props.onSourceQuoteChange}
                onContractorActionChange={props.onContractorActionChange}
                onContractorVisibilityChange={props.onContractorVisibilityChange}
                onContractorBlockingPolicyChange={props.onContractorBlockingPolicyChange}
                onAdminWorkflowPolicyChange={props.onAdminWorkflowPolicyChange}
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
                recordKeyReadOnly={props.recordKeyReadOnly}
                enabled={props.enabled}
                onEnabledChange={props.onEnabledChange}
                onRecordKeyChange={props.onRecordKeyChange}
              />

              <FormControl isRequired>
                <FormLabel>Contractor-friendly name</FormLabel>
                <Input
                  value={props.contractorDisplayName}
                  onChange={(e) => props.onContractorDisplayNameChange(e.target.value)}
                />
              </FormControl>

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
