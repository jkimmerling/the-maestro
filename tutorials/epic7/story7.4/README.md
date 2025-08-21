# Epic 7 Story 7.4: Multi-Modal Prompt Handling

## Overview

This tutorial covers the implementation of multi-modal prompt handling in The Maestro, enabling the system to format and prepare multimodal content (text, images, audio, video, documents, etc.) for direct consumption by LLM provider APIs.

The key principle is that **LLM providers handle the actual interpretation and analysis** of multimodal content. The Maestro's role is to properly format and structure this content for delivery to the providers.

## Key Features Implemented

### 1. Content Type Support
- **Text**: Plain text content and instructions
- **Image**: Base64-encoded image data with MIME type specification
- **Audio**: Audio files for provider processing
- **Video**: Video content for provider analysis
- **Document**: PDFs and other documents
- **File**: Generic file attachments

### 2. Provider-Compatible Formatting
- **Gemini Format**: Parts-based structure with text and inline_data components
- **Claude Format**: Compatible multimodal message structure
- **Universal**: Standardized format that works across providers

### 3. Content Validation
- Structure validation for all content items
- Type verification against supported content types
- Empty content filtering
- MIME type inference for non-text content

### 4. Token Estimation
- Rough token usage estimation for cost planning
- Content-type specific token calculations
- Planning support for large multimodal requests

## Architecture

### Simplified Design

```elixir
TheMaestro.Prompts.MultiModal
├── Content validation and filtering
├── Parts generation for LLM providers
├── MIME type inference
└── Token usage estimation
```

The architecture is intentionally simple - the complexity of multimodal analysis is handled by the LLM providers themselves.

### Data Flow

1. **Content Validation**: Ensure all content items have required structure
2. **MIME Type Inference**: Add MIME types where not specified
3. **Parts Generation**: Convert to LLM provider-compatible parts
4. **Token Estimation**: Calculate approximate token usage

## Usage Examples

### Basic Multi-Modal Content

```elixir
# Define multi-modal content
content = [
  %{
    type: :text,
    content: "Please analyze this error screenshot and code snippet"
  },
  %{
    type: :image,
    content: "base64_encoded_image_data...",
    mime_type: "image/png"
  },
  %{
    type: :text,
    content: "Here's the problematic function:"
  },
  %{
    type: :document,
    content: "base64_encoded_code_file...",
    mime_type: "text/plain"
  }
]

# Convert to provider-compatible parts
parts = TheMaestro.Prompts.MultiModal.content_to_parts(content)

# Result: List of parts ready for LLM provider APIs
# [
#   %{text: "Please analyze this error screenshot and code snippet"},
#   %{inline_data: %{mime_type: "image/png", data: "base64_encoded_image_data..."}},
#   %{text: "Here's the problematic function:"},
#   %{inline_data: %{mime_type: "text/plain", data: "base64_encoded_code_file..."}}
# ]
```

### Content Validation

```elixir
# Validate individual content items
valid = TheMaestro.Prompts.MultiModal.valid_content_item?(%{
  type: :image,
  content: "base64_image_data",
  mime_type: "image/jpeg"
})  # Returns: true

invalid = TheMaestro.Prompts.MultiModal.valid_content_item?(%{
  type: :image,
  content: ""  # Empty content
})  # Returns: false
```

### Token Usage Estimation

```elixir
content = [
  %{type: :text, content: "Analyze this image"},
  %{type: :image, content: "base64_data", mime_type: "image/png"},
  %{type: :video, content: "base64_video", mime_type: "video/mp4"}
]

estimated_tokens = TheMaestro.Prompts.MultiModal.estimate_token_usage(content)
# Returns approximate token count for cost planning
```

### MIME Type Inference

```elixir
# MIME types are automatically inferred when not provided
content = [
  %{type: :image, content: "image_data"},    # Infers "image/png"
  %{type: :document, content: "pdf_data"},   # Infers "application/pdf"
  %{type: :audio, content: "audio_data"}     # Infers "audio/wav"
]

parts = TheMaestro.Prompts.MultiModal.content_to_parts(content)
# MIME types automatically added to inline_data parts
```

## Integration with LLM Providers

### Google Gemini Integration

```elixir
# The parts format is directly compatible with Gemini's API
parts = MultiModal.content_to_parts(multimodal_content)

# Send to Gemini
{:ok, response} = GoogleAI.generate_content(parts, model: "gemini-1.5-pro")
```

### Anthropic Claude Integration

```elixir
# Parts can be adapted for Claude's message format
parts = MultiModal.content_to_parts(multimodal_content)

# Convert to Claude message format and send
claude_messages = convert_parts_to_claude_format(parts)
{:ok, response} = Anthropic.create_message(claude_messages)
```

## Content Type Guidelines

### Images
- **Format**: Base64-encoded image data
- **MIME Types**: `image/png`, `image/jpeg`, `image/gif`, etc.
- **Use Cases**: Screenshots, diagrams, charts, photos
- **Token Cost**: ~1000 tokens per image (estimated)

### Documents
- **Format**: Base64-encoded document data
- **MIME Types**: `application/pdf`, `text/plain`, `application/msword`, etc.
- **Use Cases**: PDFs, text files, code files, documentation
- **Token Cost**: ~1500 tokens per document (estimated)

### Audio/Video
- **Format**: Base64-encoded media data
- **MIME Types**: `audio/wav`, `video/mp4`, etc.
- **Use Cases**: Voice recordings, screen recordings, presentations
- **Token Cost**: ~2000 tokens per media file (estimated)

## Performance Considerations

### Content Size Limits
- Check provider-specific size limits before sending
- Consider splitting large documents into smaller chunks
- Use appropriate image compression before base64 encoding

### Token Usage
- Use `estimate_token_usage/1` for cost planning
- Monitor actual usage vs. estimates
- Consider content prioritization for token budget management

### Validation
- Always validate content structure before processing
- Filter out invalid or empty content items
- Ensure required MIME types are present or can be inferred

## Error Handling

### Invalid Content
The system gracefully handles invalid content by:
- Filtering out items with unsupported types
- Removing items with empty content
- Skipping malformed content structures

### Missing MIME Types
- Automatic inference for common content types
- Fallback to generic `application/octet-stream` for files
- Clear error messages for unsupported type/MIME combinations

## Testing

The implementation includes comprehensive test coverage:

```bash
# Run multi-modal tests
MIX_ENV=test mix test test/the_maestro/prompts/multimodal_test.exs

# Test specific functionality
MIX_ENV=test mix test test/the_maestro/prompts/multimodal_test.exs -k "content_to_parts"
```

### Test Coverage
- Content validation for all supported types
- Parts generation with and without MIME types
- MIME type inference
- Token usage estimation
- Provider compatibility testing
- Invalid content filtering

## Best Practices

### 1. Content Preparation
- Ensure images are properly base64-encoded
- Include explicit MIME types when possible
- Validate content before creating multimodal requests

### 2. Provider Selection
- Choose providers based on multimodal capabilities
- Test with different providers to find optimal results
- Consider cost implications of multimodal content

### 3. Error Recovery
- Always validate content structure
- Have fallbacks for unsupported content types
- Monitor token usage and implement budget controls

### 4. Performance
- Cache base64-encoded content when possible
- Consider async processing for large content sets
- Monitor provider response times and adjust accordingly

## Integration Points

### With Existing Prompt System
The multimodal system integrates seamlessly with The Maestro's existing prompt generation, adding rich media support to text-based prompts.

### With Provider Interfaces
Generated parts are compatible with major LLM provider APIs, requiring minimal adaptation for different providers.

### With Content Management
The system works with any content management approach - files, databases, streams, etc. - as long as content is available as base64-encoded strings.

## Future Enhancements

- Enhanced MIME type detection from content headers
- Streaming support for very large media files
- Provider-specific optimization recommendations
- Automated content compression and optimization
- Real-time token usage tracking and budget management

## Troubleshooting

### Common Issues

1. **Content Not Processing**: Check content structure and ensure required fields are present
2. **MIME Type Errors**: Verify MIME types are correct for content type
3. **Token Limit Exceeded**: Use token estimation to plan content inclusion
4. **Provider Errors**: Verify content format compatibility with target provider

### Debug Mode

Enable detailed logging:
```bash
export ELIXIR_LOG_LEVEL=debug
mix test test/the_maestro/prompts/multimodal_test.exs
```

This simplified multimodal system provides a clean, efficient way to prepare diverse content types for LLM provider consumption while letting the providers handle the complex analysis and interpretation tasks.