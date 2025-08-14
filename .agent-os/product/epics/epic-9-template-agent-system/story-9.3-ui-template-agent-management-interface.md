# Story 9.3: UI Template Agent Management Interface

## User Story

**As a** user of TheMaestro web interface  
**I want** a comprehensive and intuitive UI for template agent management with advanced creation, editing, discovery, and collaboration features  
**so that** I can efficiently create, customize, organize, and share template agents through a modern, responsive web interface that supports my entire template management workflow

## Acceptance Criteria

1. **Template Creation Wizard**: Step-by-step guided template creation with form validation, configuration assistance, and real-time preview
2. **Advanced Template Editor**: Rich editor with syntax highlighting, auto-completion, validation feedback, and configuration assistance
3. **Template Discovery Interface**: Powerful search and browsing experience with filtering, categorization, rating display, and recommendation engine
4. **Template Library Management**: Comprehensive library organization with collections, favorites, tagging, and sharing capabilities
5. **Real-time Collaboration Features**: Multi-user editing, commenting, version comparison, and change tracking
6. **Template Preview and Testing**: Live preview system with configuration testing, validation results, and performance metrics
7. **Template Import/Export Interface**: Drag-and-drop import, batch operations, format conversion, and export customization
8. **Analytics and Insights Dashboard**: Usage analytics, performance metrics, popularity trends, and optimization recommendations
9. **Template Rating and Review System**: Community rating interface, detailed reviews, usage context, and moderation tools
10. **Template Sharing and Publishing**: Granular permission controls, publication workflow, and team collaboration features
11. **Responsive Design Implementation**: Mobile-first design supporting tablet, desktop, and mobile devices with touch optimization
12. **Template Inheritance Visualization**: Interactive hierarchy display, dependency mapping, and inheritance configuration
13. **Configuration Validation Interface**: Real-time validation feedback, error highlighting, dependency resolution, and fix suggestions
14. **Template Comparison Tools**: Side-by-side comparison, diff visualization, merge assistance, and conflict resolution
15. **Bulk Operations Interface**: Multi-select operations, batch editing, mass import/export, and progress tracking
16. **Template Collection Management**: Collection creation, organization, sharing, and collaborative curation
17. **Advanced Search Interface**: Faceted search, saved searches, search suggestions, and intelligent filtering
18. **Template Performance Monitoring**: Real-time performance metrics, usage tracking, and optimization recommendations
19. **Template Security Dashboard**: Permission overview, access auditing, security scanning, and compliance reporting
20. **Integration Configuration Interface**: Provider setup, persona assignment, tool configuration, and MCP server management
21. **Template Marketplace Interface**: Community templates, featured collections, trending templates, and discovery recommendations
22. **Template Documentation System**: Integrated documentation editor, usage examples, parameter descriptions, and help system
23. **Template Lifecycle Management**: Version tracking, deprecation management, migration assistance, and archival tools
24. **Accessibility Compliance**: WCAG 2.1 AA compliance, keyboard navigation, screen reader support, and accessibility testing
25. **Performance Optimization**: Sub-2-second load times, lazy loading, caching strategies, and bandwidth optimization

## Technical Implementation

### Main Template Management Interface

```typescript
// components/TemplateManagement/TemplateManagementInterface.tsx
import React, { useState, useEffect, useCallback } from 'react';
import { 
  Box, 
  Container, 
  Grid, 
  Paper, 
  Typography, 
  Tabs, 
  Tab,
  Fab,
  Drawer,
  useTheme,
  useMediaQuery
} from '@mui/material';
import { Add as AddIcon } from '@mui/icons-material';

import { TemplateLibrary } from './TemplateLibrary';
import { TemplateEditor } from './TemplateEditor';
import { TemplateCreationWizard } from './TemplateCreationWizard';
import { TemplateAnalytics } from './TemplateAnalytics';
import { TemplateCollections } from './TemplateCollections';
import { TemplateMarketplace } from './TemplateMarketplace';

interface TemplateManagementInterfaceProps {
  userId: string;
  organizationId?: string;
  initialView?: 'library' | 'editor' | 'analytics' | 'collections' | 'marketplace';
}

export const TemplateManagementInterface: React.FC<TemplateManagementInterfaceProps> = ({
  userId,
  organizationId,
  initialView = 'library'
}) => {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));
  
  const [activeTab, setActiveTab] = useState(initialView);
  const [selectedTemplate, setSelectedTemplate] = useState<Template | null>(null);
  const [isCreationWizardOpen, setIsCreationWizardOpen] = useState(false);
  const [isEditorOpen, setIsEditorOpen] = useState(false);
  const [templates, setTemplates] = useState<Template[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filters, setFilters] = useState<TemplateFilters>({});

  // Load templates and setup real-time subscriptions
  useEffect(() => {
    loadTemplates();
    setupRealtimeSubscriptions();
    
    return () => cleanupSubscriptions();
  }, [userId, organizationId, searchQuery, filters]);

  const loadTemplates = useCallback(async () => {
    setLoading(true);
    try {
      const response = await templateService.getTemplates({
        userId,
        organizationId,
        search: searchQuery,
        filters,
        includeAnalytics: true
      });
      
      setTemplates(response.templates);
    } catch (error) {
      console.error('Failed to load templates:', error);
      notificationService.error('Failed to load templates');
    } finally {
      setLoading(false);
    }
  }, [userId, organizationId, searchQuery, filters]);

  const setupRealtimeSubscriptions = useCallback(() => {
    // Subscribe to template updates
    const templateSubscription = websocketService.subscribe('templates', {
      userId,
      organizationId,
      onUpdate: (updatedTemplate: Template) => {
        setTemplates(prev => prev.map(t => 
          t.id === updatedTemplate.id ? updatedTemplate : t
        ));
      },
      onDelete: (templateId: string) => {
        setTemplates(prev => prev.filter(t => t.id !== templateId));
      },
      onCreate: (newTemplate: Template) => {
        setTemplates(prev => [newTemplate, ...prev]);
      }
    });

    return () => {
      templateSubscription.unsubscribe();
    };
  }, [userId, organizationId]);

  const handleTabChange = useCallback((event: React.SyntheticEvent, newValue: string) => {
    setActiveTab(newValue);
  }, []);

  const handleTemplateSelect = useCallback((template: Template) => {
    setSelectedTemplate(template);
    setIsEditorOpen(true);
  }, []);

  const handleTemplateCreate = useCallback(() => {
    setIsCreationWizardOpen(true);
  }, []);

  const handleTemplateCreated = useCallback((newTemplate: Template) => {
    setTemplates(prev => [newTemplate, ...prev]);
    setIsCreationWizardOpen(false);
    notificationService.success('Template created successfully');
  }, []);

  const handleTemplateUpdated = useCallback((updatedTemplate: Template) => {
    setTemplates(prev => prev.map(t => 
      t.id === updatedTemplate.id ? updatedTemplate : t
    ));
    notificationService.success('Template updated successfully');
  }, []);

  const handleTemplateDeleted = useCallback((templateId: string) => {
    setTemplates(prev => prev.filter(t => t.id !== templateId));
    if (selectedTemplate?.id === templateId) {
      setSelectedTemplate(null);
      setIsEditorOpen(false);
    }
    notificationService.success('Template deleted successfully');
  }, [selectedTemplate]);

  const renderTabContent = useCallback(() => {
    switch (activeTab) {
      case 'library':
        return (
          <TemplateLibrary
            templates={templates}
            loading={loading}
            searchQuery={searchQuery}
            filters={filters}
            onSearchChange={setSearchQuery}
            onFiltersChange={setFilters}
            onTemplateSelect={handleTemplateSelect}
            onTemplateDelete={handleTemplateDeleted}
            userId={userId}
            organizationId={organizationId}
          />
        );
      
      case 'analytics':
        return (
          <TemplateAnalytics
            templates={templates}
            userId={userId}
            organizationId={organizationId}
          />
        );
      
      case 'collections':
        return (
          <TemplateCollections
            templates={templates}
            userId={userId}
            organizationId={organizationId}
            onTemplateSelect={handleTemplateSelect}
          />
        );
      
      case 'marketplace':
        return (
          <TemplateMarketplace
            userId={userId}
            organizationId={organizationId}
            onTemplateSelect={handleTemplateSelect}
            onTemplateInstall={(template) => {
              setTemplates(prev => [template, ...prev]);
              notificationService.success('Template installed successfully');
            }}
          />
        );
      
      default:
        return null;
    }
  }, [
    activeTab, 
    templates, 
    loading, 
    searchQuery, 
    filters, 
    userId, 
    organizationId,
    handleTemplateSelect,
    handleTemplateDeleted
  ]);

  return (
    <Container maxWidth="xl" sx={{ py: 3 }}>
      <Box sx={{ flexGrow: 1 }}>
        {/* Header */}
        <Box sx={{ mb: 3, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Typography variant="h4" component="h1" sx={{ fontWeight: 600 }}>
            Template Management
          </Typography>
          
          <Box sx={{ display: 'flex', gap: 2 }}>
            {/* Quick actions */}
          </Box>
        </Box>

        {/* Main Navigation Tabs */}
        <Paper sx={{ mb: 3 }}>
          <Tabs 
            value={activeTab} 
            onChange={handleTabChange}
            variant={isMobile ? "scrollable" : "standard"}
            scrollButtons="auto"
            sx={{ borderBottom: 1, borderColor: 'divider' }}
          >
            <Tab label="Template Library" value="library" />
            <Tab label="Analytics" value="analytics" />
            <Tab label="Collections" value="collections" />
            <Tab label="Marketplace" value="marketplace" />
          </Tabs>
        </Paper>

        {/* Tab Content */}
        <Box sx={{ minHeight: '600px' }}>
          {renderTabContent()}
        </Box>

        {/* Floating Action Button */}
        <Fab
          color="primary"
          aria-label="create template"
          onClick={handleTemplateCreate}
          sx={{
            position: 'fixed',
            bottom: 24,
            right: 24,
            zIndex: theme.zIndex.fab
          }}
        >
          <AddIcon />
        </Fab>

        {/* Creation Wizard Modal */}
        <TemplateCreationWizard
          open={isCreationWizardOpen}
          onClose={() => setIsCreationWizardOpen(false)}
          onTemplateCreated={handleTemplateCreated}
          userId={userId}
          organizationId={organizationId}
        />

        {/* Template Editor Drawer */}
        <Drawer
          anchor="right"
          open={isEditorOpen}
          onClose={() => setIsEditorOpen(false)}
          sx={{
            '& .MuiDrawer-paper': {
              width: isMobile ? '100%' : '60%',
              minWidth: 600,
              maxWidth: 1200
            }
          }}
        >
          {selectedTemplate && (
            <TemplateEditor
              template={selectedTemplate}
              onClose={() => setIsEditorOpen(false)}
              onSave={handleTemplateUpdated}
              onDelete={handleTemplateDeleted}
              userId={userId}
              organizationId={organizationId}
            />
          )}
        </Drawer>
      </Box>
    </Container>
  );
};

// Template Library Component
export const TemplateLibrary: React.FC<TemplateLibraryProps> = ({
  templates,
  loading,
  searchQuery,
  filters,
  onSearchChange,
  onFiltersChange,
  onTemplateSelect,
  onTemplateDelete,
  userId,
  organizationId
}) => {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));
  
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
  const [sortBy, setSortBy] = useState<SortOption>('updated_desc');
  const [selectedTemplates, setSelectedTemplates] = useState<Set<string>>(new Set());
  const [showFilters, setShowFilters] = useState(false);

  const handleBulkAction = useCallback(async (action: BulkAction) => {
    const templateIds = Array.from(selectedTemplates);
    
    try {
      switch (action) {
        case 'export':
          await templateService.bulkExport(templateIds, { format: 'json' });
          break;
        case 'delete':
          await templateService.bulkDelete(templateIds);
          templateIds.forEach(id => onTemplateDelete(id));
          break;
        case 'duplicate':
          await templateService.bulkDuplicate(templateIds);
          break;
      }
      
      setSelectedTemplates(new Set());
      notificationService.success(`Bulk ${action} completed successfully`);
    } catch (error) {
      notificationService.error(`Bulk ${action} failed`);
    }
  }, [selectedTemplates, onTemplateDelete]);

  return (
    <Box>
      {/* Search and Filter Bar */}
      <Paper sx={{ p: 2, mb: 3 }}>
        <Grid container spacing={2} alignItems="center">
          <Grid item xs={12} md={6}>
            <TemplateSearchBar
              query={searchQuery}
              onQueryChange={onSearchChange}
              placeholder="Search templates..."
              suggestions={true}
            />
          </Grid>
          
          <Grid item xs={12} md={6}>
            <Box sx={{ display: 'flex', gap: 1, justifyContent: 'flex-end', flexWrap: 'wrap' }}>
              <TemplateSortSelect
                value={sortBy}
                onChange={setSortBy}
              />
              
              <TemplateViewModeToggle
                value={viewMode}
                onChange={setViewMode}
              />
              
              <Button
                variant="outlined"
                startIcon={<FilterListIcon />}
                onClick={() => setShowFilters(!showFilters)}
              >
                Filters
              </Button>
              
              {selectedTemplates.size > 0 && (
                <TemplateBulkActions
                  selectedCount={selectedTemplates.size}
                  onAction={handleBulkAction}
                />
              )}
            </Box>
          </Grid>
        </Grid>
        
        {/* Advanced Filters */}
        <Collapse in={showFilters}>
          <Box sx={{ mt: 2, pt: 2, borderTop: 1, borderColor: 'divider' }}>
            <TemplateFilters
              filters={filters}
              onChange={onFiltersChange}
            />
          </Box>
        </Collapse>
      </Paper>

      {/* Templates Display */}
      {loading ? (
        <TemplateLibrarySkeletons count={12} viewMode={viewMode} />
      ) : templates.length === 0 ? (
        <TemplateEmptyState 
          hasSearch={Boolean(searchQuery)}
          hasFilters={Object.keys(filters).length > 0}
          onCreateTemplate={() => {}}
        />
      ) : (
        <TemplateGrid
          templates={templates}
          viewMode={viewMode}
          selectedTemplates={selectedTemplates}
          onSelectionChange={setSelectedTemplates}
          onTemplateSelect={onTemplateSelect}
          onTemplateDelete={onTemplateDelete}
          userId={userId}
          organizationId={organizationId}
        />
      )}
    </Box>
  );
};

// Template Creation Wizard
export const TemplateCreationWizard: React.FC<TemplateCreationWizardProps> = ({
  open,
  onClose,
  onTemplateCreated,
  userId,
  organizationId
}) => {
  const [currentStep, setCurrentStep] = useState(0);
  const [templateData, setTemplateData] = useState<PartialTemplate>({
    name: '',
    display_name: '',
    description: '',
    category: 'general',
    tags: [],
    provider_config: {},
    persona_config: {},
    tool_config: {},
    prompt_config: {},
    deployment_config: {}
  });
  
  const [validation, setValidation] = useState<ValidationResult>({
    isValid: false,
    errors: [],
    warnings: []
  });

  const steps = [
    {
      title: 'Basic Information',
      component: BasicInfoStep,
      isValid: () => templateData.name && templateData.description
    },
    {
      title: 'Provider Configuration',
      component: ProviderConfigStep,
      isValid: () => templateData.provider_config?.default_provider
    },
    {
      title: 'Persona Assignment',
      component: PersonaConfigStep,
      isValid: () => templateData.persona_config?.primary_persona_id
    },
    {
      title: 'Tool Configuration',
      component: ToolConfigStep,
      isValid: () => true // Optional step
    },
    {
      title: 'Prompt Setup',
      component: PromptConfigStep,
      isValid: () => true // Optional step
    },
    {
      title: 'Deployment Settings',
      component: DeploymentConfigStep,
      isValid: () => true // Optional step
    },
    {
      title: 'Review & Create',
      component: ReviewStep,
      isValid: () => validation.isValid
    }
  ];

  useEffect(() => {
    validateTemplate();
  }, [templateData]);

  const validateTemplate = useCallback(async () => {
    try {
      const result = await templateService.validateTemplate(templateData);
      setValidation(result);
    } catch (error) {
      setValidation({
        isValid: false,
        errors: ['Validation failed'],
        warnings: []
      });
    }
  }, [templateData]);

  const handleNext = useCallback(() => {
    if (currentStep < steps.length - 1) {
      setCurrentStep(currentStep + 1);
    }
  }, [currentStep, steps.length]);

  const handleBack = useCallback(() => {
    if (currentStep > 0) {
      setCurrentStep(currentStep - 1);
    }
  }, [currentStep]);

  const handleCreate = useCallback(async () => {
    try {
      const template = await templateService.createTemplate({
        ...templateData,
        author_id: userId,
        organization_id: organizationId
      });
      
      onTemplateCreated(template);
      onClose();
    } catch (error) {
      notificationService.error('Failed to create template');
    }
  }, [templateData, userId, organizationId, onTemplateCreated, onClose]);

  const CurrentStepComponent = steps[currentStep].component;

  return (
    <Dialog 
      open={open} 
      onClose={onClose}
      maxWidth="md"
      fullWidth
      fullScreen={isMobile}
    >
      <DialogTitle>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          Create New Template
          <IconButton onClick={onClose}>
            <CloseIcon />
          </IconButton>
        </Box>
      </DialogTitle>
      
      <DialogContent>
        {/* Progress Stepper */}
        <Stepper 
          activeStep={currentStep} 
          alternativeLabel={!isMobile}
          orientation={isMobile ? 'vertical' : 'horizontal'}
          sx={{ mb: 4 }}
        >
          {steps.map((step, index) => (
            <Step key={step.title}>
              <StepLabel>{step.title}</StepLabel>
            </Step>
          ))}
        </Stepper>

        {/* Step Content */}
        <CurrentStepComponent
          data={templateData}
          onChange={setTemplateData}
          validation={validation}
        />
      </DialogContent>

      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        
        <Box sx={{ flex: '1 1 auto' }} />
        
        <Button 
          disabled={currentStep === 0}
          onClick={handleBack}
        >
          Back
        </Button>
        
        {currentStep === steps.length - 1 ? (
          <Button
            variant="contained"
            onClick={handleCreate}
            disabled={!validation.isValid}
          >
            Create Template
          </Button>
        ) : (
          <Button
            variant="contained"
            onClick={handleNext}
            disabled={!steps[currentStep].isValid()}
          >
            Next
          </Button>
        )}
      </DialogActions>
    </Dialog>
  );
};

// Template Editor Component
export const TemplateEditor: React.FC<TemplateEditorProps> = ({
  template,
  onClose,
  onSave,
  onDelete,
  userId,
  organizationId
}) => {
  const [editedTemplate, setEditedTemplate] = useState<Template>(template);
  const [isDirty, setIsDirty] = useState(false);
  const [validation, setValidation] = useState<ValidationResult>({ isValid: true, errors: [], warnings: [] });
  const [activeTab, setActiveTab] = useState('basic');
  const [previewMode, setPreviewMode] = useState(false);

  useEffect(() => {
    setEditedTemplate(template);
    setIsDirty(false);
  }, [template]);

  useEffect(() => {
    validateTemplate();
  }, [editedTemplate]);

  const validateTemplate = useCallback(async () => {
    try {
      const result = await templateService.validateTemplate(editedTemplate);
      setValidation(result);
    } catch (error) {
      setValidation({
        isValid: false,
        errors: ['Validation failed'],
        warnings: []
      });
    }
  }, [editedTemplate]);

  const handleSave = useCallback(async () => {
    if (!validation.isValid) return;

    try {
      const updatedTemplate = await templateService.updateTemplate(editedTemplate.id, editedTemplate);
      onSave(updatedTemplate);
      setIsDirty(false);
      notificationService.success('Template saved successfully');
    } catch (error) {
      notificationService.error('Failed to save template');
    }
  }, [editedTemplate, validation.isValid, onSave]);

  const handleDelete = useCallback(async () => {
    try {
      await templateService.deleteTemplate(editedTemplate.id);
      onDelete(editedTemplate.id);
      onClose();
      notificationService.success('Template deleted successfully');
    } catch (error) {
      notificationService.error('Failed to delete template');
    }
  }, [editedTemplate.id, onDelete, onClose]);

  const handleFieldChange = useCallback((field: keyof Template, value: any) => {
    setEditedTemplate(prev => ({
      ...prev,
      [field]: value
    }));
    setIsDirty(true);
  }, []);

  return (
    <Box sx={{ height: '100vh', display: 'flex', flexDirection: 'column' }}>
      {/* Editor Header */}
      <Box sx={{ p: 2, borderBottom: 1, borderColor: 'divider' }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
          <Typography variant="h6">
            Edit Template: {editedTemplate.display_name || editedTemplate.name}
          </Typography>
          
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              variant="outlined"
              startIcon={<PreviewIcon />}
              onClick={() => setPreviewMode(!previewMode)}
            >
              {previewMode ? 'Edit' : 'Preview'}
            </Button>
            
            <Button
              variant="contained"
              onClick={handleSave}
              disabled={!isDirty || !validation.isValid}
            >
              Save
            </Button>
            
            <IconButton onClick={onClose}>
              <CloseIcon />
            </IconButton>
          </Box>
        </Box>

        {/* Validation Status */}
        {validation.errors.length > 0 && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {validation.errors.join(', ')}
          </Alert>
        )}
        
        {validation.warnings.length > 0 && (
          <Alert severity="warning" sx={{ mb: 2 }}>
            {validation.warnings.join(', ')}
          </Alert>
        )}

        {/* Editor Tabs */}
        <Tabs value={activeTab} onChange={(e, value) => setActiveTab(value)}>
          <Tab label="Basic Info" value="basic" />
          <Tab label="Provider" value="provider" />
          <Tab label="Persona" value="persona" />
          <Tab label="Tools" value="tools" />
          <Tab label="Prompts" value="prompts" />
          <Tab label="Deployment" value="deployment" />
          <Tab label="Advanced" value="advanced" />
        </Tabs>
      </Box>

      {/* Editor Content */}
      <Box sx={{ flex: 1, overflow: 'auto' }}>
        {previewMode ? (
          <TemplatePreview template={editedTemplate} />
        ) : (
          <TemplateEditTabs
            activeTab={activeTab}
            template={editedTemplate}
            onChange={handleFieldChange}
            validation={validation}
          />
        )}
      </Box>

      {/* Editor Footer */}
      <Box sx={{ p: 2, borderTop: 1, borderColor: 'divider' }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Box>
            {isDirty && (
              <Chip
                label="Unsaved changes"
                color="warning"
                size="small"
                icon={<UnsavedIcon />}
              />
            )}
          </Box>
          
          <Box sx={{ display: 'flex', gap: 2 }}>
            <Button
              color="error"
              startIcon={<DeleteIcon />}
              onClick={() => {
                // Show confirmation dialog
                if (window.confirm('Are you sure you want to delete this template?')) {
                  handleDelete();
                }
              }}
            >
              Delete
            </Button>
          </Box>
        </Box>
      </Box>
    </Box>
  );
};
```

### Phoenix LiveView Backend

```elixir
# lib/the_maestro_web/live/template_management_live.ex
defmodule TheMaestroWeb.TemplateManagementLive do
  use TheMaestroWeb, :live_view
  
  alias TheMaestro.AgentTemplates
  alias TheMaestro.AgentTemplates.Template
  alias TheMaestro.Accounts

  @impl Phoenix.LiveView
  def mount(_params, %{"user_token" => user_token} = _session, socket) do
    user = Accounts.get_user_by_session_token(user_token)
    
    if connected?(socket) do
      # Subscribe to template updates
      AgentTemplates.subscribe_to_template_updates(user.id)
      AgentTemplates.subscribe_to_organization_templates(user.organization_id)
    end

    socket = 
      socket
      |> assign(:user, user)
      |> assign(:page_title, "Template Management")
      |> assign(:active_tab, "library")
      |> assign(:templates, [])
      |> assign(:loading, true)
      |> assign(:search_query, "")
      |> assign(:filters, %{})
      |> assign(:selected_template, nil)
      |> assign(:show_creation_modal, false)
      |> assign(:show_editor, false)
      |> load_templates()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"tab" => tab} = _params, _uri, socket) when tab in ["library", "analytics", "collections", "marketplace"] do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_params(%{"template_id" => template_id}, _uri, socket) do
    case AgentTemplates.get_template(template_id, user_id: socket.assigns.user.id) do
      {:ok, template} ->
        socket = 
          socket
          |> assign(:selected_template, template)
          |> assign(:show_editor, true)
        
        {:noreply, socket}
      
      {:error, :not_found} ->
        socket = 
          socket
          |> put_flash(:error, "Template not found")
          |> push_redirect(to: Routes.template_management_path(socket, :index))
        
        {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"query" => query}, socket) do
    socket = 
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)
      |> load_templates()

    {:noreply, socket}
  end

  def handle_event("filter", filters, socket) do
    socket = 
      socket
      |> assign(:filters, filters)
      |> assign(:loading, true)
      |> load_templates()

    {:noreply, socket}
  end

  def handle_event("select_template", %{"template_id" => template_id}, socket) do
    case AgentTemplates.get_template(template_id, user_id: socket.assigns.user.id) do
      {:ok, template} ->
        socket = 
          socket
          |> assign(:selected_template, template)
          |> assign(:show_editor, true)
        
        {:noreply, socket}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to load template")}
    end
  end

  def handle_event("create_template", _params, socket) do
    {:noreply, assign(socket, :show_creation_modal, true)}
  end

  def handle_event("close_creation_modal", _params, socket) do
    {:noreply, assign(socket, :show_creation_modal, false)}
  end

  def handle_event("close_editor", _params, socket) do
    socket = 
      socket
      |> assign(:show_editor, false)
      |> assign(:selected_template, nil)
    
    {:noreply, socket}
  end

  def handle_event("delete_template", %{"template_id" => template_id}, socket) do
    case AgentTemplates.delete_template(template_id, socket.assigns.user.id) do
      :ok ->
        socket = 
          socket
          |> put_flash(:info, "Template deleted successfully")
          |> load_templates()
        
        {:noreply, socket}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete template: #{reason}")}
    end
  end

  def handle_event("bulk_action", %{"action" => action, "template_ids" => template_ids}, socket) do
    case perform_bulk_action(action, template_ids, socket.assigns.user.id) do
      {:ok, result} ->
        socket = 
          socket
          |> put_flash(:info, "Bulk #{action} completed: #{result}")
          |> load_templates()
        
        {:noreply, socket}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Bulk #{action} failed: #{reason}")}
    end
  end

  # Real-time update handlers
  @impl Phoenix.LiveView
  def handle_info({:template_created, template}, socket) do
    if template.author_id == socket.assigns.user.id or template.is_public do
      templates = [template | socket.assigns.templates]
      {:noreply, assign(socket, :templates, templates)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:template_updated, template}, socket) do
    templates = Enum.map(socket.assigns.templates, fn t ->
      if t.id == template.id, do: template, else: t
    end)
    
    socket = assign(socket, :templates, templates)
    
    # Update selected template if it's the one being edited
    socket = if socket.assigns.selected_template && socket.assigns.selected_template.id == template.id do
      assign(socket, :selected_template, template)
    else
      socket
    end
    
    {:noreply, socket}
  end

  def handle_info({:template_deleted, template_id}, socket) do
    templates = Enum.reject(socket.assigns.templates, fn t -> t.id == template_id end)
    
    socket = assign(socket, :templates, templates)
    
    # Close editor if deleted template was selected
    socket = if socket.assigns.selected_template && socket.assigns.selected_template.id == template_id do
      socket
      |> assign(:selected_template, nil)
      |> assign(:show_editor, false)
    else
      socket
    end
    
    {:noreply, socket}
  end

  # Private functions
  defp load_templates(socket) do
    user = socket.assigns.user
    search_query = socket.assigns.search_query
    filters = socket.assigns.filters
    
    Task.start(fn ->
      templates = AgentTemplates.search_templates(search_query, filters, %{
        user_id: user.id,
        organization_id: user.organization_id,
        include_analytics: true
      })
      
      send(self(), {:templates_loaded, templates})
    end)
    
    socket
  end

  defp perform_bulk_action("export", template_ids, user_id) do
    AgentTemplates.bulk_operation(:export, template_ids, user_id, %{format: "json"})
  end

  defp perform_bulk_action("delete", template_ids, user_id) do
    AgentTemplates.bulk_operation(:delete, template_ids, user_id)
  end

  defp perform_bulk_action("duplicate", template_ids, user_id) do
    AgentTemplates.bulk_operation(:duplicate, template_ids, user_id)
  end

  defp perform_bulk_action(_action, _template_ids, _user_id) do
    {:error, "Unknown action"}
  end
end
```

### LiveView Template

```html
<!-- lib/the_maestro_web/live/template_management_live.html.heex -->
<div class="template-management-interface">
  <!-- Header -->
  <.header class="template-management-header">
    <:title>Template Management</:title>
    <:subtitle>Create, manage, and organize your AI agent templates</:subtitle>
    <:actions>
      <.button phx-click="create_template" class="template-create-btn">
        <.icon name="hero-plus" /> Create Template
      </.button>
    </:actions>
  </.header>

  <!-- Navigation Tabs -->
  <div class="template-tabs">
    <.tab_navigation active_tab={@active_tab}>
      <:tab name="library" label="Template Library" />
      <:tab name="analytics" label="Analytics" />
      <:tab name="collections" label="Collections" />
      <:tab name="marketplace" label="Marketplace" />
    </.tab_navigation>
  </div>

  <!-- Tab Content -->
  <div class="template-content">
    <%= case @active_tab do %>
      <% "library" -> %>
        <.live_component 
          module={TheMaestroWeb.TemplateLibraryComponent}
          id="template-library"
          templates={@templates}
          loading={@loading}
          search_query={@search_query}
          filters={@filters}
          user={@user}
        />
      
      <% "analytics" -> %>
        <.live_component 
          module={TheMaestroWeb.TemplateAnalyticsComponent}
          id="template-analytics"
          templates={@templates}
          user={@user}
        />
      
      <% "collections" -> %>
        <.live_component 
          module={TheMaestroWeb.TemplateCollectionsComponent}
          id="template-collections"
          user={@user}
        />
      
      <% "marketplace" -> %>
        <.live_component 
          module={TheMaestroWeb.TemplateMarketplaceComponent}
          id="template-marketplace"
          user={@user}
        />
    <% end %>
  </div>

  <!-- Creation Modal -->
  <%= if @show_creation_modal do %>
    <.live_component 
      module={TheMaestroWeb.TemplateCreationWizardComponent}
      id="template-creation-wizard"
      user={@user}
    />
  <% end %>

  <!-- Template Editor -->
  <%= if @show_editor and @selected_template do %>
    <.live_component 
      module={TheMaestroWeb.TemplateEditorComponent}
      id="template-editor"
      template={@selected_template}
      user={@user}
    />
  <% end %>
</div>

<style>
  .template-management-interface {
    @apply min-h-screen bg-gray-50;
  }

  .template-management-header {
    @apply bg-white shadow-sm border-b border-gray-200 px-6 py-4;
  }

  .template-tabs {
    @apply bg-white border-b border-gray-200;
  }

  .template-content {
    @apply p-6;
  }

  .template-create-btn {
    @apply bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg inline-flex items-center gap-2 transition-colors;
  }
</style>
```

## Module Structure

```
lib/the_maestro_web/live/template_management/
├── template_management_live.ex       # Main LiveView controller
├── template_library_component.ex    # Template library interface
├── template_creation_wizard_component.ex # Template creation wizard
├── template_editor_component.ex     # Template editor interface
├── template_analytics_component.ex  # Analytics dashboard
├── template_collections_component.ex # Collections management
├── template_marketplace_component.ex # Template marketplace
├── template_preview_component.ex    # Template preview
└── components/
    ├── template_card.ex             # Individual template card
    ├── template_filters.ex          # Advanced filtering
    ├── template_search.ex           # Search interface
    ├── bulk_actions.ex             # Bulk operation controls
    └── rating_system.ex            # Rating and review system
```

## Integration Points

1. **Epic 5 Integration**: Provider selection and authentication UI components
2. **Epic 6 Integration**: MCP server configuration interfaces
3. **Epic 7 Integration**: Prompt editing and configuration UI
4. **Epic 8 Integration**: Persona selection and assignment interfaces
5. **Real-time Updates**: WebSocket integration for live collaboration
6. **Analytics Integration**: Usage tracking and performance monitoring

## Performance Considerations

- Component lazy loading for faster initial page loads
- Virtual scrolling for large template lists
- Debounced search with intelligent caching
- Image optimization for template thumbnails
- Bundle splitting for optimal loading performance

## Security Considerations

- Client-side input validation with server-side confirmation
- CSRF protection for all form submissions
- Content Security Policy implementation
- XSS protection for user-generated content
- Permission validation at component level

## Dependencies

- Epic 5: Model Choice & Authentication System
- Epic 6: MCP Protocol Implementation
- Epic 7: Enhanced Prompt Handling System
- Epic 8: Persona Management System
- Phoenix LiveView for real-time UI updates
- React with Material-UI for rich interface components

## Definition of Done

- [ ] Template creation wizard with guided step-by-step process
- [ ] Advanced template editor with syntax highlighting and validation
- [ ] Comprehensive template discovery with search and filtering
- [ ] Template library management with collections and favorites
- [ ] Real-time collaboration features with change tracking
- [ ] Template preview and testing capabilities
- [ ] Template import/export interface with multiple formats
- [ ] Analytics dashboard with usage insights and performance metrics
- [ ] Community rating and review system with moderation
- [ ] Template sharing and publishing with permission controls
- [ ] Responsive design supporting mobile, tablet, and desktop devices
- [ ] Template inheritance visualization with interactive hierarchy display
- [ ] Real-time configuration validation with error highlighting
- [ ] Template comparison tools with side-by-side diff visualization
- [ ] Bulk operations interface with progress tracking
- [ ] Template collection management with sharing capabilities
- [ ] Advanced search with faceted filtering and suggestions
- [ ] Performance monitoring dashboard with optimization recommendations
- [ ] Security dashboard with permission overview and audit logging
- [ ] Integration configuration interfaces for all Epic dependencies
- [ ] Template marketplace with community features
- [ ] Integrated documentation system with examples
- [ ] Template lifecycle management with version tracking
- [ ] WCAG 2.1 AA accessibility compliance
- [ ] Sub-2-second load times with performance optimization
- [ ] Comprehensive unit tests with >95% coverage
- [ ] Integration tests with all backend services
- [ ] Cross-browser compatibility testing (Chrome, Firefox, Safari, Edge)
- [ ] Mobile responsiveness testing on iOS and Android
- [ ] Performance testing with 1000+ concurrent users
- [ ] Security penetration testing and vulnerability assessment
- [ ] User acceptance testing with design review
- [ ] Complete UI/UX documentation and style guide