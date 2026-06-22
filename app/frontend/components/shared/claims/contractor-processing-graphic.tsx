import { Box, Flex, Text, VStack } from '@chakra-ui/react';
import { keyframes } from '@emotion/react';
import { ArrowClockwise } from '@phosphor-icons/react';
import React from 'react';

const orbitSpin = keyframes`
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
`;

const pulseGlow = keyframes`
  0%, 100% { opacity: 0.55; transform: scale(0.95); }
  50% { opacity: 0.95; transform: scale(1.04); }
`;

const storyFade = keyframes`
  0% { opacity: 0; transform: translateY(8px) scale(0.98); filter: blur(3px); }
  18% { opacity: 1; transform: translateY(0) scale(1); filter: blur(0); }
  82% { opacity: 1; transform: translateY(0) scale(1); filter: blur(0); }
  100% { opacity: 0; transform: translateY(-7px) scale(0.99); filter: blur(2px); }
`;

export function ContractorProcessingGraphic({ label }: { label: string }) {
  return (
    <VStack spacing={4} py={8} align="center">
      <Box position="relative" w="168px" h="168px">
        <Box
          position="absolute"
          inset="10px"
          borderRadius="full"
          bg="radial-gradient(circle at 35% 30%, rgba(255,255,255,0.98), rgba(188,229,255,0.42) 42%, rgba(0,104,183,0.08) 72%)"
          boxShadow="0 22px 55px rgba(0, 85, 140, 0.22), inset 0 1px 18px rgba(255,255,255,0.9)"
          animation={`${pulseGlow} 2.7s ease-in-out infinite`}
          sx={{
            '@media (prefers-reduced-motion: reduce)': {
              animation: 'none',
            },
          }}
        />
        <Flex
          position="absolute"
          inset="0"
          align="center"
          justify="center"
          borderRadius="full"
          bg="conic-gradient(from 120deg, rgba(10,132,207,0), rgba(61,177,255,0.82), rgba(214,244,255,0.95), rgba(10,132,207,0.08), rgba(10,132,207,0))"
          sx={{
            mask: 'radial-gradient(circle, transparent 53%, black 55%)',
            WebkitMask: 'radial-gradient(circle, transparent 53%, black 55%)',
            animation: `${orbitSpin} 1.45s linear infinite`,
            '@media (prefers-reduced-motion: reduce)': {
              animation: `${orbitSpin} 5s linear infinite`,
            },
          }}
        />
        <Flex
          position="absolute"
          inset="0"
          align="center"
          justify="center"
          color="#0068b7"
          filter="drop-shadow(0 12px 20px rgba(0, 104, 183, 0.22))"
          sx={{
            animation: `${orbitSpin} 2.3s cubic-bezier(.62,.02,.32,1) infinite`,
            '@media (prefers-reduced-motion: reduce)': {
              animation: 'none',
            },
          }}
        >
          <ArrowClockwise size={104} weight="duotone" />
        </Flex>
        <Box
          position="absolute"
          right="22px"
          top="30px"
          w="16px"
          h="16px"
          borderRadius="full"
          bg="linear-gradient(135deg, #ffffff, #42c7ff)"
          boxShadow="0 0 24px rgba(66, 199, 255, 0.9)"
        />
      </Box>
      <Text
        key={label}
        fontSize="xl"
        fontWeight="700"
        letterSpacing="0.02em"
        color="rgba(15, 42, 67, 0.92)"
        minH="32px"
        textAlign="center"
        animation={`${storyFade} 3s ease-in-out infinite`}
        sx={{
          '@media (prefers-reduced-motion: reduce)': {
            animation: 'none',
          },
        }}
      >
        {label}
      </Text>
    </VStack>
  );
}
