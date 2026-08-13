import { Box, Flex } from '@chakra-ui/react';
import { keyframes } from '@emotion/react';
import { Check, ClockCountdown, SpinnerGap, Warning, X } from '@phosphor-icons/react';
import React from 'react';
import { IngestStepDiagnostic } from './ingest-diagnostic-drawer';

type PipeCellProps = {
  step: IngestStepDiagnostic;
  first: boolean;
  last: boolean;
  onOpen: () => void;
};

const STATUS_COLORS: Record<string, { main: string; dark: string; light: string }> = {
  succeeded: { main: '#2f9e67', dark: '#17613d', light: '#75d6a5' },
  recovered: { main: '#65788c', dark: '#35485a', light: '#a9bac9' },
  failed: { main: '#d64550', dark: '#8f1f29', light: '#f48a92' },
  retrying: { main: '#dd8b22', dark: '#92570c', light: '#f6c56f' },
  running: { main: '#267fca', dark: '#14538a', light: '#70baf4' },
  in_progress: { main: '#267fca', dark: '#14538a', light: '#70baf4' },
  queued: { main: '#c89d28', dark: '#7f6113', light: '#f4d875' },
};

const activeFlow = keyframes`
  from { background-position: 0 0; }
  to { background-position: 0 20px; }
`;

const activePulse = keyframes`
  0%, 100% { box-shadow: inset 0 1px 3px rgba(255,255,255,0.62), inset 0 -4px 7px rgba(8,34,55,0.32), 0 0 0 2px rgba(38,127,202,0.14), 0 5px 14px -7px rgba(20,83,138,0.95); }
  50% { box-shadow: inset 0 1px 3px rgba(255,255,255,0.72), inset 0 -4px 7px rgba(8,34,55,0.26), 0 0 0 6px rgba(38,127,202,0.06), 0 7px 18px -6px rgba(20,83,138,1); }
`;

const normalizedStatus = (step: IngestStepDiagnostic) =>
  String(step.display_status || step.status || 'queued')
    .trim()
    .toLowerCase();

function StatusGlyph({ status }: { status: string }) {
  if (status === 'succeeded') return <Check size={14} weight="bold" />;
  if (status === 'failed') return <X size={14} weight="bold" />;
  if (status === 'retrying') return <Warning size={14} weight="fill" />;
  if (status === 'running' || status === 'in_progress') return <SpinnerGap size={14} weight="bold" />;
  return <ClockCountdown size={14} weight="bold" />;
}

export function IngestProcessPipeCell({ step, first, last, onOpen }: PipeCellProps) {
  const status = normalizedStatus(step);
  const colors = STATUS_COLORS[status] || STATUS_COLORS.queued;
  const active = status === 'running' || status === 'in_progress';

  return (
    <Box position="absolute" top="-2px" bottom="-2px" left="50%" w="52px" minW="52px" transform="translateX(-50%)">
      <Box
        position="absolute"
        zIndex={0}
        top={first ? '50%' : 0}
        bottom={last ? '50%' : 0}
        left="50%"
        w="18px"
        transform="translateX(-50%)"
        borderLeft="1px solid #344653"
        borderRight="1px solid #263743"
        bg="linear-gradient(90deg, #263743 0%, #718391 9%, #dce7ed 23%, #8fa2b0 39%, #f7fbfd 51%, #879aa8 66%, #c7d4dc 80%, #40525f 94%, #1f303c 100%)"
        boxShadow="inset 3px 0 4px rgba(255,255,255,0.5), inset -3px 0 5px rgba(11,28,40,0.42), 2px 0 8px -5px rgba(13,39,58,0.9)"
        sx={{
          '&::before': {
            content: '""',
            position: 'absolute',
            top: 0,
            bottom: 0,
            left: '50%',
            width: '5px',
            transform: 'translateX(-50%)',
            borderRadius: '999px',
            background: active
              ? `repeating-linear-gradient(180deg, ${colors.light} 0, ${colors.main} 8px, ${colors.dark} 10px, ${colors.light} 20px)`
              : `linear-gradient(90deg, ${colors.dark}, ${colors.main} 42%, ${colors.light} 55%, ${colors.main} 72%, ${colors.dark})`,
            boxShadow: `0 0 5px ${colors.main}, inset 1px 0 rgba(255,255,255,0.45)`,
            animation: active ? `${activeFlow} 720ms linear infinite` : 'none',
          },
          '&::after': {
            content: '""',
            position: 'absolute',
            top: 0,
            bottom: 0,
            left: '3px',
            width: '2px',
            background: 'linear-gradient(90deg, rgba(255,255,255,0.68), rgba(255,255,255,0.06))',
          },
          '@media (prefers-reduced-motion: reduce)': { '&::before': { animation: 'none' } },
        }}
      />

      <Box
        as="button"
        type="button"
        aria-label={`Open ${String(step.step_type || 'ingest')} step details`}
        position="absolute"
        zIndex={2}
        top="50%"
        left="50%"
        transform="translate(-50%, -50%)"
        cursor="pointer"
        borderRadius="full"
        _focusVisible={{ outline: '2px solid', outlineColor: 'blue.500', outlineOffset: '2px' }}
        onClick={onOpen}
      >
        <Flex
          w="44px"
          h="44px"
          align="center"
          justify="center"
          borderRadius="full"
          border="1px solid #263b4a"
          bg="conic-gradient(from 18deg, #f7fbfd, #657987 12%, #d9e5eb 23%, #405563 36%, #f5fafc 49%, #718592 62%, #dce7ec 74%, #3b4e5c 87%, #f7fbfd)"
          boxShadow="inset 0 0 0 1px rgba(255,255,255,0.7), inset 0 0 0 5px rgba(44,62,75,0.25), 0 8px 18px -9px rgba(20,48,68,0.95)"
          transition="transform 140ms ease, filter 140ms ease"
          _hover={{ transform: 'scale(1.08)', filter: 'brightness(1.06)' }}
        >
          <Flex
            position="relative"
            w="28px"
            h="28px"
            align="center"
            justify="center"
            borderRadius="full"
            color="white"
            border={`2px solid ${colors.dark}`}
            bg={`radial-gradient(circle at 34% 24%, rgba(255,255,255,0.95) 0%, ${colors.light} 18%, ${colors.main} 48%, ${colors.dark} 100%)`}
            boxShadow={`inset 0 1px 3px rgba(255,255,255,0.62), inset 0 -4px 7px rgba(8,34,55,0.32), 0 0 8px ${colors.main}`}
            animation={active ? `${activePulse} 1.65s ease-in-out infinite` : undefined}
            sx={{
              '&::after': {
                content: '""',
                position: 'absolute',
                top: '3px',
                left: '6px',
                width: '9px',
                height: '4px',
                borderRadius: 'full',
                transform: 'rotate(-18deg)',
                background: 'rgba(255,255,255,0.62)',
                filter: 'blur(0.4px)',
                pointerEvents: 'none',
              },
              '@media (prefers-reduced-motion: reduce)': { animation: 'none' },
            }}
          >
            <Box position="relative" zIndex={1} display="flex">
              <StatusGlyph status={status} />
            </Box>
          </Flex>
        </Flex>
      </Box>
    </Box>
  );
}
