import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
  Box,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tr,
} from '@chakra-ui/react';
import React from 'react';
import { ActionSignal, ImprovementAction } from './action-signals';

export function ActionSignalsOverview({ actions }: { actions: ImprovementAction[] }) {
  return (
    <Box as="section" aria-label="Improvement options and signals" mb={8}>
      <Accordion allowMultiple>
        {actions.map((action, index) => (
          <AccordionItem key={action.id}>
            <h2>
              <AccordionButton py={3} px={3} _expanded={{ bg: 'gray.50' }}>
                <Text as="span" flex="1" textAlign="left" fontWeight="semibold">
                  Option {index + 1}. {action.title}
                </Text>
                <AccordionIcon ml={3} />
              </AccordionButton>
            </h2>
            <AccordionPanel px={{ base: 1, md: 3 }} pb={6}>
              {action.id === 'observe' ? (
                <Text fontSize="sm" color="gray.700">
                  {action.purpose}
                </Text>
              ) : (
                <SignalTable actionTitle={action.title} signals={action.primarySignals} />
              )}
            </AccordionPanel>
          </AccordionItem>
        ))}
      </Accordion>
    </Box>
  );
}

function SignalTable({ actionTitle, signals }: { actionTitle: string; signals: ActionSignal[] }) {
  return (
    <Box overflowX="auto">
      <Table size="sm" variant="simple" minW="800px" aria-label={`${actionTitle}: signals`}>
        <Thead>
          <Tr>
            <Th width="24%">Signal</Th>
            <Th width="1%" px={2} whiteSpace="nowrap">
              Value
            </Th>
            <Th
              width="1%"
              px={2}
              whiteSpace="nowrap"
              title="Distinct invoices with this signal, as a percentage of all invoices assessed by this rule in the current report period."
            >
              % of invoices
            </Th>
            <Th whiteSpace="nowrap">What to investigate</Th>
          </Tr>
        </Thead>
        <Tbody>
          {signals.map((row) => (
            <SignalRow key={row.id} signal={row} />
          ))}
        </Tbody>
      </Table>
    </Box>
  );
}

function SignalRow({ signal }: { signal: ActionSignal }) {
  const percentage =
    signal.invoiceCount !== null && signal.totalInvoiceCount !== null && signal.totalInvoiceCount > 0
      ? (signal.invoiceCount / signal.totalInvoiceCount) * 100
      : null;
  const percentageLabel =
    percentage === null ? '—' : percentage > 0 && percentage < 0.1 ? '<0.1%' : `${Number(percentage.toFixed(1))}%`;
  const percentageDescription = ['average_rounds', 'median_rounds', 'maximum_rounds'].includes(signal.id)
    ? 'Not applicable to round statistics.'
    : signal.totalInvoiceCount === 0
      ? 'No invoices assessed by this rule in the current report period.'
      : percentage === null
        ? 'Invoice percentage is unavailable.'
        : `${signal.invoiceCount.toLocaleString()} of ${signal.totalInvoiceCount.toLocaleString()} distinct invoices assessed by this rule in the current report period.`;
  return (
    <Tr verticalAlign="top">
      <Td py={2}>
        <Text>{signal.label}</Text>
      </Td>
      <Td px={2} py={2} whiteSpace="nowrap">
        <Text fontWeight="semibold">{signal.value === null ? 'Not available' : signal.value.toLocaleString()}</Text>
      </Td>
      <Td px={2} py={2} whiteSpace="nowrap" title={percentageDescription}>
        {percentageLabel}
      </Td>
      <Td py={2} fontSize="sm">
        {signal.detail} {signal.interpretation}
      </Td>
    </Tr>
  );
}
