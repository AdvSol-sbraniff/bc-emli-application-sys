import { Box, BoxProps, Container, Flex, Heading } from '@chakra-ui/react';
import React from 'react';

interface IThinBlueTitleBarProps extends BoxProps {
  title: string;
}

export const ThinBlueTitleBar = ({ title, ...rest }: IThinBlueTitleBarProps) => {
  return (
    <Box h="fit-content" bg="theme.blueGradient" {...rest}>
      <Container
        as={Flex}
        direction="column"
        justifyContent="center"
        alignContent="center"
        maxW="container.lg"
        minHeight="96px"
      >
        <Heading as="h1" color="greys.white" fontSize="1.75rem">
          {title}
        </Heading>
      </Container>
    </Box>
  );
};
