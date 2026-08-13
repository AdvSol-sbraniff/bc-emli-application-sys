import { Badge, Box, Flex, Text } from '@chakra-ui/react';
import { keyframes } from '@emotion/react';
import React from 'react';

type ComplianceSpectrumProps = {
  complianceScore?: number | string | null;
  result?: unknown;
  sourceEngine?: unknown;
  compact?: boolean;
  assessmentContent?: React.ReactNode;
};

type ComplianceBand = {
  key: 'pass' | 'info' | 'warn' | 'fail';
  label: string;
  range: string;
  color: string;
  glow: string;
  textColor: string;
};

const COMPLIANCE_BANDS: ComplianceBand[] = [
  {
    key: 'pass',
    label: 'Pass',
    range: '75–100',
    color: '#27ae60',
    glow: 'rgba(39, 174, 96, 0.34)',
    textColor: 'white',
  },
  {
    key: 'info',
    label: 'Info',
    range: '50–74',
    color: '#2684d9',
    glow: 'rgba(38, 132, 217, 0.34)',
    textColor: 'white',
  },
  {
    key: 'warn',
    label: 'Warn',
    range: '25–49',
    color: '#f4c542',
    glow: 'rgba(244, 197, 66, 0.42)',
    textColor: '#3d2c00',
  },
  {
    key: 'fail',
    label: 'Fail',
    range: '0–24',
    color: '#df3b46',
    glow: 'rgba(223, 59, 70, 0.36)',
    textColor: 'white',
  },
];

const RESULT_BANDS = Object.fromEntries(COMPLIANCE_BANDS.map((band) => [band.key, band])) as Record<
  ComplianceBand['key'],
  ComplianceBand
>;

const cardArrival = keyframes`
  from { opacity: 0; transform: translateY(10px) scale(0.985); }
  to { opacity: 1; transform: translateY(0) scale(1); }
`;

const markerArrival = keyframes`
  from { opacity: 0; transform: translateX(18px) scale(0.92); }
  to { opacity: 1; transform: translateX(0) scale(1); }
`;

const markerHalo = keyframes`
  0% { opacity: 0; transform: translate(-50%, -50%) scale(0.45); }
  35% { opacity: 0.72; }
  100% { opacity: 0; transform: translate(-50%, -50%) scale(2.5); }
`;

const scoreBand = (score: number): ComplianceBand => {
  if (score >= 75) return RESULT_BANDS.pass;
  if (score >= 50) return RESULT_BANDS.info;
  if (score >= 25) return RESULT_BANDS.warn;
  return RESULT_BANDS.fail;
};

const normalizedResult = (result: unknown): ComplianceBand['key'] | null => {
  const value = String(result ?? '')
    .trim()
    .toLowerCase();
  return value === 'pass' || value === 'info' || value === 'warn' || value === 'fail' ? value : null;
};

export function ComplianceSpectrum({
  complianceScore,
  result,
  sourceEngine,
  compact = false,
  assessmentContent,
}: ComplianceSpectrumProps) {
  if (String(sourceEngine ?? '').toLowerCase() !== 'genai') return null;
  if (complianceScore == null || complianceScore === '') return null;

  const rawScore = Number(complianceScore);
  if (!Number.isFinite(rawScore)) return null;

  const score = Math.min(100, Math.max(0, Math.round(rawScore)));
  const band = scoreBand(score);
  const recordedResult = normalizedResult(result);
  const resultBand = recordedResult ? RESULT_BANDS[recordedResult] : band;
  const markerTop = 100 - score;
  const markerOffset = score >= 90 ? '-18%' : score <= 10 ? '-82%' : '-50%';

  return (
    <Box
      mb={compact ? 0 : '24px'}
      position="relative"
      overflow="hidden"
      borderRadius="2xl"
      borderWidth="1px"
      borderColor="rgba(82, 117, 154, 0.2)"
      bg="linear-gradient(145deg, rgba(255,255,255,0.98) 0%, rgba(241,247,253,0.98) 52%, rgba(231,241,251,0.96) 100%)"
      boxShadow="0 22px 52px -34px rgba(14, 54, 92, 0.72), inset 0 1px 0 rgba(255,255,255,0.92)"
      px={compact ? '14px' : { base: '16px', sm: '22px' }}
      pt={compact ? '16px' : '20px'}
      pb={compact ? '14px' : '17px'}
      display={assessmentContent ? 'grid' : 'block'}
      gridTemplateColumns={assessmentContent ? { base: '1fr', md: '166px minmax(0, 1fr)' } : undefined}
      columnGap={assessmentContent ? { base: 0, md: '4px' } : undefined}
      animation={`${cardArrival} 420ms cubic-bezier(.2,.8,.2,1) both`}
      sx={{
        '&::before': {
          content: '""',
          position: 'absolute',
          width: '240px',
          height: '240px',
          borderRadius: '999px',
          top: '-145px',
          right: '-85px',
          background: `radial-gradient(circle, ${band.glow} 0%, rgba(255,255,255,0) 68%)`,
          pointerEvents: 'none',
        },
        '&::after': {
          content: '""',
          position: 'absolute',
          width: '190px',
          height: '190px',
          borderRadius: '999px',
          bottom: '-138px',
          left: '-72px',
          background: 'radial-gradient(circle, rgba(38,132,217,0.16) 0%, rgba(255,255,255,0) 70%)',
          pointerEvents: 'none',
        },
        '@media (prefers-reduced-motion: reduce)': {
          animation: 'none',
        },
      }}
    >
      <Badge
        position="absolute"
        zIndex={2}
        top={compact ? '14px' : '18px'}
        right={compact ? '14px' : { base: '16px', sm: '22px' }}
        px="10px"
        py="5px"
        borderRadius="full"
        bg={resultBand.color}
        color={resultBand.textColor}
        boxShadow={`0 8px 20px -10px ${resultBand.glow}`}
        fontSize="10px"
        letterSpacing="0.08em"
      >
        {recordedResult || band.key}
      </Badge>

      <Box
        position="relative"
        zIndex={1}
        gridColumn="1"
        mt={compact && assessmentContent ? '34px' : compact ? '4px' : '8px'}
        display="grid"
        gridTemplateColumns={
          compact
            ? '34px 40px minmax(74px, 1fr)'
            : { base: '58px 52px minmax(86px, 1fr)', sm: '88px 70px minmax(150px, 1fr)' }
        }
        columnGap={compact ? '4px' : { base: '8px', sm: '16px' }}
        h={compact ? '224px' : '248px'}
      >
        <Box position="relative" aria-hidden="true">
          {COMPLIANCE_BANDS.map((item, index) => (
            <Flex
              key={item.key}
              position="absolute"
              top={`${index * 25 + 12.5}%`}
              right={0}
              transform="translateY(-50%)"
              direction="column"
              align="flex-end"
              lineHeight={1.05}
            >
              <Text
                fontSize={compact ? '9px' : { base: '10px', sm: '11px' }}
                fontWeight="800"
                color="gray.700"
                textTransform="uppercase"
              >
                {item.label}
              </Text>
              <Text mt="4px" fontSize="9px" color="gray.500" fontVariantNumeric="tabular-nums">
                {item.range}
              </Text>
            </Flex>
          ))}
        </Box>

        <Box
          role="img"
          aria-label={`Compliance score ${score} out of 100, ${band.label}`}
          position="relative"
          h={compact ? '224px' : '248px'}
          borderRadius="999px"
          p="5px"
          bg="rgba(255,255,255,0.84)"
          border="1px solid rgba(34, 66, 98, 0.18)"
          boxShadow={`0 17px 38px -20px ${band.glow}, inset 0 0 0 1px rgba(255,255,255,0.78)`}
        >
          <Box
            position="relative"
            overflow="hidden"
            h="100%"
            borderRadius="999px"
            bg="linear-gradient(to bottom, #27ae60 0%, #27ae60 25%, #2684d9 25%, #2684d9 50%, #f4c542 50%, #f4c542 75%, #df3b46 75%, #df3b46 100%)"
            boxShadow="inset 8px 0 15px rgba(255,255,255,0.23), inset -9px 0 17px rgba(15,42,67,0.2)"
            sx={{
              '&::before': {
                content: '""',
                position: 'absolute',
                inset: '0 auto 0 13%',
                width: '22%',
                borderRadius: '999px',
                background: 'linear-gradient(to right, rgba(255,255,255,0.48), rgba(255,255,255,0.06))',
              },
            }}
          >
            {[25, 50, 75].map((value) => (
              <Box
                key={value}
                position="absolute"
                top={`${value}%`}
                left={0}
                right={0}
                h="1px"
                bg="rgba(255,255,255,0.72)"
                boxShadow="0 1px 0 rgba(15,42,67,0.16)"
              />
            ))}
          </Box>

          <Box
            position="absolute"
            zIndex={3}
            top={`${markerTop}%`}
            left="50%"
            w="24px"
            h="24px"
            borderRadius="full"
            border={`2px solid ${band.color}`}
            animation={`${markerHalo} 1100ms 260ms ease-out both`}
            sx={{
              '@media (prefers-reduced-motion: reduce)': {
                animation: 'none',
                opacity: 0,
              },
            }}
          />

          <Box
            position="absolute"
            zIndex={4}
            top={`${markerTop}%`}
            left="-6px"
            right="-6px"
            h="3px"
            transform="translateY(-50%)"
            borderRadius="full"
            bg="#102f4d"
            boxShadow="0 1px 0 rgba(255,255,255,0.8), 0 4px 10px rgba(10,35,58,0.28)"
          >
            <Box
              position="absolute"
              top="50%"
              left="50%"
              transform="translate(-50%, -50%) rotate(45deg)"
              w="10px"
              h="10px"
              bg="white"
              border="3px solid #102f4d"
              borderRadius="2px"
            />
          </Box>
        </Box>

        <Box position="relative" h={compact ? '224px' : '248px'}>
          <Flex
            position="absolute"
            top={`${markerTop}%`}
            left={compact ? '-4px' : { base: '-10px', sm: '-16px' }}
            transform={`translateY(${markerOffset})`}
            align="center"
            maxW="100%"
          >
            <Box w={compact ? '6px' : { base: '14px', sm: '24px' }} h="3px" bg="#102f4d" flexShrink={0} />
            <Flex
              align="baseline"
              gap="4px"
              px={compact ? '7px' : { base: '10px', sm: '14px' }}
              py={compact ? '8px' : { base: '8px', sm: '10px' }}
              borderRadius="xl"
              bg="rgba(255,255,255,0.96)"
              border="1px solid rgba(16,47,77,0.17)"
              boxShadow={`0 14px 30px -16px ${band.glow}, 0 6px 16px -12px rgba(16,47,77,0.75)`}
              animation={`${markerArrival} 480ms 160ms cubic-bezier(.2,.85,.25,1) both`}
              sx={{
                '@media (prefers-reduced-motion: reduce)': {
                  animation: 'none',
                },
              }}
            >
              <Text
                fontSize={compact ? 'xl' : { base: '2xl', sm: '3xl' }}
                lineHeight={1}
                fontWeight="800"
                color="#102f4d"
                letterSpacing="-0.04em"
                fontVariantNumeric="tabular-nums"
              >
                {score}
              </Text>
              <Text fontSize="xs" fontWeight="700" color="gray.500">
                / 100
              </Text>
            </Flex>
          </Flex>
        </Box>
      </Box>

      {assessmentContent && (
        <Box
          position="relative"
          zIndex={1}
          minW={0}
          gridColumn={{ base: '1', md: '2' }}
          gridRow={{ base: 'auto', md: '1' }}
          mt={{ base: '20px', md: 0 }}
          px={{ base: '2px', md: 0 }}
          pt={{ base: 0, md: '34px' }}
          pb={{ base: 0, md: '2px' }}
        >
          {assessmentContent}
        </Box>
      )}
    </Box>
  );
}
