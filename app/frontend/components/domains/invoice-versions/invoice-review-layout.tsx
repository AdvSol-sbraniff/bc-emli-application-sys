import { Box } from '@chakra-ui/react';
import React, { useRef, useState } from 'react';
import {
  clampAuxiliaryPanelWidth,
  MAX_AUXILIARY_PANEL_WIDTH,
  MIN_AUXILIARY_PANEL_WIDTH,
} from './use-invoice-review-layout';

export const InvoiceReviewLayout = ({ children }: { children: React.ReactNode }) => (
  <Box display="flex" gap="16px" flex="1" minH={0} overflowX="auto">
    {children}
  </Box>
);

export const InvoiceReviewRightRegion = ({ children }: { children: React.ReactNode }) => (
  <Box display="flex" gap="16px" flex="1 1 0" minH={0}>
    {children}
  </Box>
);

export const INVOICE_REVIEW_PANEL_GAP = 16;
export const MIN_DOCUMENT_PANEL_WIDTH = 480;
const MIN_MAIN_PANEL_WIDTH = 480;

const clampMainPanelWidth = (width: number, maxWidth: number) =>
  Math.min(Math.max(MIN_MAIN_PANEL_WIDTH, maxWidth), Math.max(MIN_MAIN_PANEL_WIDTH, width));

export const InvoiceReviewMainPanel = ({
  children,
  hasRightRegion,
  rightRegionMinimumWidth,
}: {
  children: React.ReactNode;
  hasRightRegion: boolean;
  rightRegionMinimumWidth: number;
}) => {
  const panelRef = useRef<HTMLDivElement | null>(null);
  const resizeStartRef = useRef<{ pointerX: number; width: number; maxWidth: number } | null>(null);
  const [width, setWidth] = useState<number | null>(null);

  const renderedWidth = () => panelRef.current?.getBoundingClientRect().width ?? MIN_MAIN_PANEL_WIDTH;
  const availableWidth = () =>
    Math.max(
      MIN_MAIN_PANEL_WIDTH,
      (panelRef.current?.parentElement?.clientWidth ?? MIN_MAIN_PANEL_WIDTH) -
        INVOICE_REVIEW_PANEL_GAP -
        rightRegionMinimumWidth,
    );

  const resizedWidth = (pointerX: number) => {
    const start = resizeStartRef.current;
    return start ? clampMainPanelWidth(start.width + pointerX - start.pointerX, start.maxWidth) : renderedWidth();
  };

  const finishResize = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!resizeStartRef.current) return;
    setWidth(resizedWidth(event.clientX));
    resizeStartRef.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  return (
    <Box
      ref={panelRef}
      position="relative"
      p="0"
      overflow="auto"
      minW={`${MIN_MAIN_PANEL_WIDTH}px`}
      maxW="100%"
      w={!hasRightRegion || width === null ? 'auto' : `${width}px`}
      flex={!hasRightRegion ? '1 1 auto' : width === null ? '1 1 0' : `0 0 ${width}px`}
    >
      {children}
      {hasRightRegion ? (
        <Box
          role="separator"
          aria-label="Resize main and right panels"
          aria-orientation="vertical"
          aria-valuemin={MIN_MAIN_PANEL_WIDTH}
          aria-valuenow={Math.round(width ?? renderedWidth())}
          tabIndex={0}
          position="absolute"
          top={0}
          right={0}
          bottom={0}
          w="8px"
          cursor="col-resize"
          zIndex={3}
          borderRightWidth="2px"
          borderRightColor="gray.200"
          sx={{ touchAction: 'none' }}
          _hover={{ borderRightColor: 'blue.400', bg: 'blue.50' }}
          _focusVisible={{ borderRightColor: 'blue.500', bg: 'blue.50', outline: 'none' }}
          onPointerDown={(event) => {
            const currentWidth = renderedWidth();
            resizeStartRef.current = {
              pointerX: event.clientX,
              width: currentWidth,
              maxWidth: availableWidth(),
            };
            setWidth(currentWidth);
            event.currentTarget.setPointerCapture(event.pointerId);
          }}
          onPointerMove={(event) => {
            if (!resizeStartRef.current) return;
            setWidth(resizedWidth(event.clientX));
          }}
          onPointerUp={finishResize}
          onPointerCancel={finishResize}
          onKeyDown={(event) => {
            if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
            event.preventDefault();
            const nextWidth = renderedWidth() + (event.key === 'ArrowRight' ? 20 : -20);
            setWidth(clampMainPanelWidth(nextWidth, availableWidth()));
          }}
        />
      ) : null}
    </Box>
  );
};

type InvoiceReviewAuxiliaryPanelProps = {
  children: React.ReactNode;
  width: number;
  onWidthChange: (width: number) => void;
  fillAvailableWidth?: boolean;
};

export const InvoiceReviewAuxiliaryPanel = ({
  children,
  width,
  onWidthChange,
  fillAvailableWidth = false,
}: InvoiceReviewAuxiliaryPanelProps) => {
  const resizeStartRef = useRef<{ pointerX: number; width: number } | null>(null);

  const resizedWidth = (pointerX: number) => {
    const start = resizeStartRef.current;
    return start ? clampAuxiliaryPanelWidth(start.width + start.pointerX - pointerX) : width;
  };

  const finishResize = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!resizeStartRef.current) return;
    onWidthChange(resizedWidth(event.clientX));
    resizeStartRef.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  return (
    <Box
      position="relative"
      flex={fillAvailableWidth ? `1 1 ${width}px` : `0 0 ${width}px`}
      w={fillAvailableWidth ? 'auto' : `${width}px`}
      minW={`${width}px`}
      maxW={fillAvailableWidth ? 'none' : `${width}px`}
      alignSelf="flex-start"
      maxH="calc(100vh - 150px)"
      overflowY="auto"
      borderWidth="1px"
      borderColor="gray.200"
      borderRadius="xl"
      bg="white"
      boxShadow="sm"
    >
      {!fillAvailableWidth ? (
        <Box
          role="separator"
          aria-label="Resize auxiliary panel"
          aria-orientation="vertical"
          aria-valuemin={MIN_AUXILIARY_PANEL_WIDTH}
          aria-valuemax={MAX_AUXILIARY_PANEL_WIDTH}
          aria-valuenow={width}
          tabIndex={0}
          position="absolute"
          top={0}
          bottom={0}
          left={0}
          w="8px"
          cursor="col-resize"
          zIndex={2}
          sx={{ touchAction: 'none' }}
          _hover={{ bg: 'blue.100' }}
          _focusVisible={{ bg: 'blue.200', outline: '2px solid', outlineColor: 'blue.500' }}
          onPointerDown={(event) => {
            resizeStartRef.current = {
              pointerX: event.clientX,
              width,
            };
            event.currentTarget.setPointerCapture(event.pointerId);
          }}
          onPointerMove={(event) => {
            if (!resizeStartRef.current) return;
            onWidthChange(resizedWidth(event.clientX));
          }}
          onPointerUp={finishResize}
          onPointerCancel={finishResize}
          onKeyDown={(event) => {
            if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
            event.preventDefault();
            onWidthChange(width + (event.key === 'ArrowLeft' ? 20 : -20));
          }}
        />
      ) : null}
      {children}
    </Box>
  );
};
