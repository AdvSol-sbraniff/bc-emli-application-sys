import { Box, BoxProps, Container, Flex, Heading } from '@chakra-ui/react';
import React from 'react';

interface ILightGradientTitleBarProps extends BoxProps {
  title: string;
}

export const LightGradientTitleBar = ({ title, ...rest }: ILightGradientTitleBarProps) => {
  return (
    <Box
      h="fit-content"
      bg="linear-gradient(180deg, rgba(49, 130, 206, 0.16) 0%, rgba(235, 248, 255, 0.72) 42%, rgba(255, 255, 255, 0.96) 100%)"
      {...rest}
    >
      <Container
        as={Flex}
        direction="column"
        justifyContent="center"
        alignContent="center"
        maxW="container.lg"
        minHeight="96px"
      >
        <Heading as="h1" color="blue.900" fontSize="1.75rem" fontWeight="semibold">
          {title}
        </Heading>
      </Container>
    </Box>
  );
};
