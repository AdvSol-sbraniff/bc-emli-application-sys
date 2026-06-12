import React from 'react';
import { SupportingDocumentTypeFieldsAdminScreen } from '../supporting-document-type-fields-admin';

export default function SupportingDocumentGroupTypeFieldsAdminScreen() {
  return (
    <SupportingDocumentTypeFieldsAdminScreen
      config={{
        basePath: '/supporting-document-group-type-fields-admin',
        listEndpointName: 'group_located_fields',
        rowEndpointName: 'supporting_document_group_type_located_fields',
        listTitle: 'Supporting Document Group Fields',
        createTitle: 'Add Supporting Document Group Field',
        editTitle: 'Edit Supporting Document Group Field',
        helperText:
          'Manage located-field tasks that are extracted from a grouped evidence set, such as a before/after photo pair.',
        loadRowsError: 'Failed to load supporting document group fields.',
        loadEditorError: 'Failed to load supporting document group field.',
        saveError: 'Failed to save supporting document group field.',
        editAriaLabel: 'Edit supporting document group field',
      }}
    />
  );
}
