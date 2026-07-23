import { Flex, Radio, RadioGroup, Text, Tooltip } from '@chakra-ui/react';
import React from 'react';

export type ViewerPanelMode = 'fullscreen' | 'document' | 'revision';

type ViewerPanelModeSelectorProps = {
  value: ViewerPanelMode;
  onChange: (value: ViewerPanelMode) => void;
  includeRevision?: boolean;
  showTooltips?: boolean;
};

const OPTIONS: Array<{ value: ViewerPanelMode; label: string; hint: string }> = [
  {
    value: 'fullscreen',
    label: 'Full screen',
    hint: 'Use the full width for invoice details and hide the right-hand panel.',
  },
  {
    value: 'document',
    label: 'Document',
    hint: 'Show the invoice details beside the document viewer.',
  },
  {
    value: 'revision',
    label: 'Revision issues',
    hint: 'Show the invoice details beside the revision issue tracker.',
  },
];

export const ViewerPanelModeSelector = ({
  value,
  onChange,
  includeRevision = true,
  showTooltips = true,
}: ViewerPanelModeSelectorProps) => {
  const [openHint, setOpenHint] = React.useState<ViewerPanelMode | null>(null);

  const handleChange = (nextValue: string) => {
    setOpenHint(null);
    onChange(nextValue as ViewerPanelMode);
  };

  return (
    <RadioGroup value={value} onChange={handleChange} aria-label="Viewer layout">
      <Flex align="center" gap={{ base: 2, md: 4 }} flexWrap="wrap">
        {OPTIONS.filter((option) => includeRevision || option.value !== 'revision').map((option) => {
          const radio = (
            <Radio value={option.value} size="sm" onClick={() => setOpenHint(null)}>
              <Text as="span" fontSize="xs" fontWeight="semibold" whiteSpace="nowrap">
                {option.label}
              </Text>
            </Radio>
          );

          return showTooltips ? (
            <Tooltip
              key={option.value}
              label={option.hint}
              hasArrow
              isOpen={openHint === option.value}
              closeOnPointerDown
              onOpen={() => setOpenHint(option.value)}
              onClose={() => setOpenHint((current) => (current === option.value ? null : current))}
            >
              {radio}
            </Tooltip>
          ) : (
            <React.Fragment key={option.value}>{radio}</React.Fragment>
          );
        })}
      </Flex>
    </RadioGroup>
  );
};
