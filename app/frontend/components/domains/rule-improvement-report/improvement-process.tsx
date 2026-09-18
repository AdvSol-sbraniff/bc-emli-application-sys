import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
  Box,
  Link,
  ListItem,
  OrderedList,
  Stack,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Text,
} from '@chakra-ui/react';
import React, { useState } from 'react';
import { Link as RouterLink } from 'react-router-dom';
import { ImprovementAction } from './action-signals';
import { RuleImprovementStepHelp } from './improvement-guide-help';
import { ImprovementStep, improvementSteps } from './improvement-steps';
import { RuleRow } from './types';

function StepGuidance({
  step,
  isCodeRule,
  rule,
  actions,
}: {
  step: ImprovementStep;
  isCodeRule: boolean;
  rule: RuleRow;
  actions: ImprovementAction[];
}) {
  return (
    <Box fontSize="sm">
      <Text mb={3}>{step.purpose}</Text>
      <OrderedList spacing={3} mb={5}>
        {step.instructions.map((instruction) => (
          <ListItem key={instruction}>{instruction}</ListItem>
        ))}
      </OrderedList>
      <Stack spacing={4} mb={5}>
        {step.examples.map((example) => (
          <Box key={example.title} borderLeftWidth="3px" borderColor="blue.200" pl={4}>
            <Text as="h4" fontWeight="semibold" mb={1}>
              {example.title}
            </Text>
            <Text>{example.description}</Text>
          </Box>
        ))}
      </Stack>
      <Text mb={2}>
        <strong>Where you do this: </strong>
        {step.screens}
      </Text>
      {step.links && (
        <Stack direction={{ base: 'column', md: 'row' }} spacing={{ base: 2, md: 5 }} mb={3}>
          {step.links.map((link) => (
            <Link
              key={link.to}
              as={RouterLink}
              to={link.to}
              target="_blank"
              rel="noopener noreferrer"
              color="blue.700"
              textDecoration="underline"
            >
              {link.label} (new tab)
            </Link>
          ))}
        </Stack>
      )}
      <Text>
        <strong>What you should have afterwards: </strong>
        {step.outcome}
      </Text>
      {step.note && (
        <Text color="gray.600" mt={3}>
          {step.note}
        </Text>
      )}
      <RuleImprovementStepHelp step={step.number} isCodeRule={isCodeRule} rule={rule} actions={actions} />
    </Box>
  );
}

export function RuleImprovementProcess({
  isCodeRule,
  rule,
  actions,
  children,
}: {
  isCodeRule: boolean;
  rule: RuleRow;
  actions: ImprovementAction[];
  children: [React.ReactNode, React.ReactNode, React.ReactNode];
}) {
  const [selectedStep, setSelectedStep] = useState(1);
  const [helpOpen, setHelpOpen] = useState(false);
  const steps = improvementSteps(isCodeRule);
  const workspaces = { options: children[0], evidence: children[1], packages: children[2] };

  return (
    <Box as="section" aria-label="Rule improvement process" minW={0}>
      <Tabs index={selectedStep} onChange={setSelectedStep} variant="unstyled" isLazy lazyBehavior="keepMounted">
        <TabList aria-label="Rule improvement process steps" overflowX="auto" gap={1} p={1}>
          {steps.map((step, index) => {
            const selected = selectedStep === index;
            return (
              <Tab
                key={step.number}
                aria-label={`Step ${step.number}: ${step.label}`}
                flex="1 0 138px"
                minH="108px"
                flexDirection="column"
                position="relative"
                isolation="isolate"
                pl={index === 0 ? 3 : 7}
                pr={6}
                py={3}
                color={selected ? 'white' : 'blue.900'}
                _before={{
                  content: '""',
                  position: 'absolute',
                  inset: 0,
                  zIndex: -1,
                  bg: selected ? 'blue.700' : 'blue.50',
                  clipPath:
                    index === 0
                      ? 'polygon(0 0, calc(100% - 18px) 0, 100% 50%, calc(100% - 18px) 100%, 0 100%)'
                      : 'polygon(0 0, calc(100% - 18px) 0, 100% 50%, calc(100% - 18px) 100%, 0 100%, 18px 50%)',
                }}
                _hover={{ _before: { bg: selected ? 'blue.800' : 'blue.100' } }}
                _focusVisible={{ outline: '3px solid', outlineColor: 'blue.500', outlineOffset: '1px' }}
              >
                <Text as="span" fontSize="xs" fontWeight="bold" mb={1}>
                  Step {step.number}:
                </Text>
                <Text as="span" fontSize="md" fontWeight="semibold" lineHeight="short" whiteSpace="normal">
                  {step.label}
                </Text>
              </Tab>
            );
          })}
        </TabList>
        <TabPanels>
          {steps.map((step) => (
            <TabPanel key={step.number} px={0} pt={4} pb={0}>
              {step.workspace ? (
                <>
                  <Accordion
                    allowToggle
                    index={helpOpen ? 0 : -1}
                    onChange={(index) => setHelpOpen(index === 0)}
                    mb={5}
                  >
                    <AccordionItem borderWidth="1px" borderColor="gray.200" borderRadius="md" overflow="hidden">
                      <Box as="h3">
                        <AccordionButton py={3} _expanded={{ bg: 'blue.50', color: 'blue.900' }}>
                          <Text flex="1" textAlign="left" fontWeight="semibold">
                            Help for Step {step.number}: {step.label}
                          </Text>
                          <AccordionIcon />
                        </AccordionButton>
                      </Box>
                      <AccordionPanel pt={4} pb={5}>
                        <StepGuidance step={step} isCodeRule={isCodeRule} rule={rule} actions={actions} />
                      </AccordionPanel>
                    </AccordionItem>
                  </Accordion>
                  {workspaces[step.workspace]}
                </>
              ) : (
                <Box borderLeftWidth="3px" borderColor="blue.600" pl={4}>
                  <Text as="h3" fontSize="lg" fontWeight="semibold" mb={3}>
                    Step {step.number}: {step.label}
                  </Text>
                  <StepGuidance step={step} isCodeRule={isCodeRule} rule={rule} actions={actions} />
                </Box>
              )}
            </TabPanel>
          ))}
        </TabPanels>
      </Tabs>
    </Box>
  );
}
