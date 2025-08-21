# Story 7.4: Multi-Modal Prompt Handling

## User Story
**As an** Agent,  
**I want** simple and direct multi-modal prompt handling that passes images, documents, and other content directly to the provider API,  
**so that** I can leverage the provider's native multi-modal capabilities without complex client-side processing.

## Acceptance Criteria

### Simple Multi-Modal Architecture
1. **Direct Provider Integration**: Multi-modal content is converted to provider format and sent directly:
   ```elixir
   defmodule TheMaestro.Prompts.MultiModal do
     @supported_formats [
       :text,      # Text content and instructions
       :image,     # Images (PNG, JPEG, GIF, WebP)
       :document,  # PDFs and other documents
       :audio,     # Audio files for supported providers
       :video      # Video files for supported providers
     ]
     
     def create_multimodal_prompt(content_items, prompt_text, provider \\ :gemini) do
       parts = convert_to_provider_parts(content_items, prompt_text, provider)
       
       %{
         role: "user",
         parts: parts
       }
     end
     
     defp convert_to_provider_parts(content_items, prompt_text, :gemini) do
       # Start with text prompt
       parts = [%{text: prompt_text}]
       
       # Add multi-modal content items as inline_data parts
       multi_modal_parts = Enum.map(content_items, fn item ->
         case item.type do
           :image ->
             %{
               inline_data: %{
                 data: Base.encode64(item.data),
                 mime_type: item.mime_type
               }
             }
           :document when item.mime_type == "application/pdf" ->
             %{
               inline_data: %{
                 data: Base.encode64(item.data),
                 mime_type: "application/pdf"
               }
             }
           _ ->
             %{text: "[Unsupported content type: #{item.type}]"}
         end
       end)
       
       parts ++ multi_modal_parts
     end
   end
   ```

2. **File Content Processing**: Simple file reading and encoding for provider APIs:
   ```elixir
   defmodule TheMaestro.Prompts.ContentProcessor do
     def process_file(file_path) do
       case File.read(file_path) do
         {:ok, data} ->
           mime_type = determine_mime_type(file_path)
           
           %ContentItem{
             type: classify_content_type(mime_type),
             data: data,
             mime_type: mime_type,
             file_path: file_path,
             size: byte_size(data)
           }
           
         {:error, reason} ->
           {:error, "Cannot read file #{file_path}: #{reason}"}
       end
     end
     
     defp determine_mime_type(file_path) do
       case Path.extname(file_path) |> String.downcase() do
         ".jpg" -> "image/jpeg"
         ".jpeg" -> "image/jpeg"
         ".png" -> "image/png"
         ".gif" -> "image/gif"
         ".webp" -> "image/webp"
         ".pdf" -> "application/pdf"
         ".mp4" -> "video/mp4"
         ".wav" -> "audio/wav"
         ".mp3" -> "audio/mp3"
         _ -> "application/octet-stream"
       end
     end
     
     defp classify_content_type(mime_type) do
       cond do
         String.starts_with?(mime_type, "image/") -> :image
         String.starts_with?(mime_type, "video/") -> :video
         String.starts_with?(mime_type, "audio/") -> :audio
         mime_type == "application/pdf" -> :document
         true -> :unknown
       end
     end
   end
   ```

### Provider Integration
3. **Provider-Specific Formatting**: Format multi-modal content for different providers:
   ```elixir
   defmodule TheMaestro.Prompts.ProviderAdapter do
     def format_for_provider(content_items, prompt_text, provider) do
       case provider do
         :gemini ->
           format_for_gemini(content_items, prompt_text)
           
         :openai ->
           format_for_openai(content_items, prompt_text)
           
         :claude ->
           format_for_claude(content_items, prompt_text)
           
         _ ->
           {:error, "Unsupported provider: #{provider}"}
       end
     end
     
     defp format_for_gemini(content_items, prompt_text) do
       parts = [%{text: prompt_text}]
       
       media_parts = Enum.map(content_items, fn item ->
         case item.type do
           :image ->
             %{
               inline_data: %{
                 data: Base.encode64(item.data),
                 mime_type: item.mime_type
               }
             }
           :document ->
             %{
               inline_data: %{
                 data: Base.encode64(item.data),
                 mime_type: item.mime_type
               }
             }
           _ ->
             %{text: "[#{String.upcase(to_string(item.type))} CONTENT: #{item.file_path}]"}
         end
       end)
       
       %{
         role: "user",
         parts: parts ++ media_parts
       }
     end
     
     defp format_for_openai(content_items, prompt_text) do
       # OpenAI uses message content array format
       content = [%{type: "text", text: prompt_text}]
       
       media_content = Enum.map(content_items, fn item ->
         case item.type do
           :image ->
             %{
               type: "image_url",
               image_url: %{
                 url: "data:#{item.mime_type};base64,#{Base.encode64(item.data)}"
               }
             }
           _ ->
             # OpenAI doesn't support other multi-modal types, convert to text
             %{
               type: "text", 
               text: "[#{String.upcase(to_string(item.type))} CONTENT: #{item.file_path}]"
             }
         end
       end)
       
       %{
         role: "user",
         content: content ++ media_content
       }
     end
     
     defp format_for_claude(content_items, prompt_text) do
       # Claude uses message content array format similar to OpenAI
       content = [%{type: "text", text: prompt_text}]
       
       media_content = Enum.map(content_items, fn item ->
         case item.type do
           :image ->
             %{
               type: "image",
               source: %{
                 type: "base64",
                 media_type: item.mime_type,
                 data: Base.encode64(item.data)
               }
             }
           :document when item.mime_type == "application/pdf" ->
             %{
               type: "document",
               source: %{
                 type: "base64",
                 media_type: item.mime_type,
                 data: Base.encode64(item.data)
               }
             }
           _ ->
             # For unsupported types, convert to text description
             %{
               type: "text", 
               text: "[#{String.upcase(to_string(item.type))} CONTENT: #{item.file_path}]"
             }
         end
       end)
       
       %{
         role: "user",
         content: content ++ media_content
       }
     end
   end
   ```

### Message Integration
4. **Message Structure Integration**: Integrate multi-modal content into existing message handling:
   ```elixir
   defmodule TheMaestro.Prompts.MessageIntegrator do
     def integrate_multimodal_content(%Message{} = message, content_items) do
       case message.provider do
         :gemini ->
           parts = build_gemini_parts(message.content, content_items)
           %{message | parts: parts}
           
         _ ->
           # For providers that don't support multi-modal, convert to text descriptions
           enhanced_content = add_content_descriptions(message.content, content_items)
           %{message | content: enhanced_content}
       end
     end
     
     defp build_gemini_parts(text_content, content_items) do
       text_parts = if text_content && text_content != "" do
         [%{text: text_content}]
       else
         []
       end
       
       media_parts = Enum.map(content_items, fn item ->
         %{
           inline_data: %{
             data: Base.encode64(item.data),
             mime_type: item.mime_type
           }
         }
       end)
       
       text_parts ++ media_parts
     end
     
     defp add_content_descriptions(text_content, content_items) do
       descriptions = Enum.map(content_items, fn item ->
         "[#{String.upcase(to_string(item.type))}: #{item.file_path} (#{item.mime_type})]"
       end)
       
       [text_content | descriptions]
       |> Enum.filter(&(&1 && &1 != ""))
       |> Enum.join("\n\n")
     end
   end
   ```

## Technical Implementation

### Simple Multi-Modal Module Structure
```elixir
lib/the_maestro/prompts/multimodal/
├── multimodal_prompt.ex      # Main multi-modal prompt coordinator
├── content_processor.ex      # File reading and MIME type detection
├── provider_adapter.ex       # Provider-specific format conversion
├── message_integrator.ex     # Integration with existing message system
└── content_item.ex           # Content item data structure
```

### Data Structures
5. **Content Item Structure**: Simple content representation:
   ```elixir
   defmodule TheMaestro.Prompts.MultiModal.ContentItem do
     defstruct [
       :type,        # :image, :document, :audio, :video, :unknown
       :data,        # Binary file data
       :mime_type,   # MIME type string
       :file_path,   # Original file path
       :size         # Size in bytes
     ]
     
     @type t :: %__MODULE__{
       type: atom(),
       data: binary(),
       mime_type: String.t(),
       file_path: String.t(),
       size: integer()
     }
   end
   ```

### Provider Integration
6. **Direct Provider API Usage**: Send formatted content directly to provider APIs:
   - **Gemini**: Uses `inline_data` parts with base64-encoded content
   - **OpenAI**: Uses message content arrays with image URLs or base64 data
   - **Claude**: Uses message content with media attachments
   - **Fallback**: Convert to text descriptions for non-multimodal providers

## Dependencies
- Stories 7.1-7.3 (System Instructions, Context Enhancement, Provider Optimization)
- Existing Gemini provider implementation
- Base64 encoding/decoding capabilities
- File system access for reading content files

## Definition of Done
- [x] Simple multi-modal prompt system architecture implemented
- [x] File content processing for images, PDFs, and basic media types
- [x] Provider-specific formatting implemented for all three providers:
  - [x] Gemini: `inline_data` parts format with base64 content
  - [x] OpenAI: `content` array format with `image_url` and data URLs
  - [x] Claude: `content` array format with `image` and `document` types
- [x] Integration with existing message handling system
- [x] Content item data structure and processing functions
- [x] MIME type detection and classification
- [x] Base64 encoding for binary content
- [x] Fallback text descriptions for unsupported content types per provider
- [x] Error handling for file reading and processing
- [x] Basic validation of file sizes and types
- [x] Integration testing with all supported provider APIs
- [x] Unit tests for content processing and provider formatting
- [x] Provider-specific test coverage for message formatting
- [x] Documentation and usage examples for all providers
- [x] Tutorial created in `tutorials/epic7/story7.4/`

## Implementation Notes
This story follows the **gemini-cli approach** of sending multi-modal content directly to the provider API without complex client-side processing. The provider (Gemini) handles all the sophisticated analysis, transcription, and understanding capabilities natively. Our implementation focuses on:

1. **File Reading**: Simple file system access to read binary content
2. **Format Conversion**: Convert content to provider-expected format (base64 + MIME type)
3. **Direct Transmission**: Send formatted content directly to provider API
4. **Provider Processing**: Let the provider handle all analysis and understanding

This approach is simpler, more reliable, and leverages the provider's native multi-modal capabilities rather than attempting to duplicate complex processing on the client side.