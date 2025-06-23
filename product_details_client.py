#!/usr/bin/env python3
import base64
import json
import requests
import argparse
from pathlib import Path


def get_product_summary_with_findings(image_path, findings):
    """
    Python implementation of the getProductSummaryWithFindings function from the Flutter app.
    This function sends an image and extracted findings to the API and streams back product descriptions
    for visually impaired users.
    
    Args:
        image_path (str): Path to the image file to be processed
        findings (str): Text findings extracted from the image (text, labels, web info)
        
    Returns:
        None: Prints the streamed response to stdout
    """
    try:
        # Read image and encode to base64
        with open(image_path, 'rb') as image_file:
            image_bytes = image_file.read()
            base64_image = base64.b64encode(image_bytes).decode('utf-8')
        
        # Set up API endpoint and headers
        url = 'http://192.168.1.125:1234/v1/chat/completions'
        headers = {'Content-Type': 'application/json'}
        
        # Create messages payload similar to the Dart implementation
        messages = [
            {
                "role": "system",
                "content": """You are a helpful assistant for visually impaired users. You will receive product images and extracted findings (text, labels, web info). Use both the image and findings to identify the product. Your response must be in a purely conversational, natural language form suitable for text-to-speech, without any markdown, markup, or formatting symbols. Do not use headings, lists, or special characters—just plain sentences. Limit your response to 2-3 concise sentences. Focus on what the product is and only the most important details, such as name, type, flavor, weight, and any special or limited edition information. Do not include unnecessary information or long explanations. If you cannot identify the product, say so. If the image is blurry or unclear, mention that as well. Avoid using phrases like 'I see' or 'I can tell you that'. Keep it withing 2-3 sentences. If you notice any potential dangers, mention them first.""",
            },
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": findings},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{base64_image}",
                            "detail": "high",
                        },
                    },
                ],
            },
        ]
        
        # Create request body
        body = {
            "model": "openbmb/minicpm-o-2_6",
            "messages": messages,
            "temperature": 0.3,
            "max_tokens": -1,
            "stream": True,
        }
        
        print("Sending image and findings to API for product identification...")
        print(f"\nFindings: {findings}\n")
        
        # Send the request with streaming enabled
        with requests.post(url, json=body, headers=headers, stream=True) as response:
            response.raise_for_status()
            
            # Process the streaming response
            complete_response = ""
            for line in response.iter_lines():
                if line:
                    line_text = line.decode('utf-8').strip()
                    
                    if line_text == '[DONE]':
                        print("\n[DONE]")
                        break
                        
                    if line_text.startswith('data: '):
                        line_text = line_text.replace('data: ', '', 1)
                        
                    try:
                        parsed_chunk = json.loads(line_text)
                        content = parsed_chunk['choices'][0]['delta'].get('content')
                        if content:
                            print(content, end='', flush=True)
                            complete_response += content
                    except json.JSONDecodeError as e:
                        print(f"\nError parsing chunk: {e}")
                    except KeyError as e:
                        print(f"\nUnexpected response format: {e}")
            
            print("\n\nComplete product description:")
            print(complete_response)
            
    except FileNotFoundError:
        print(f"Error: Image file '{image_path}' not found.")
    except requests.exceptions.RequestException as e:
        print(f"Error sending product information to API: {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")


def analyze_product_and_get_summary(image_path):
    """
    Two-step process similar to the Flutter app:
    1. Call vision backend for findings (text, labels, web entities)
    2. Send image and findings to VLM for product summary
    
    Args:
        image_path (str): Path to the image file to be processed
    """
    try:
        # Step 1: Call vision backend for findings
        vision_url = 'http://192.168.1.125:8001/analyze-product/'
        
        print("Step 1: Analyzing image to extract text, labels, and web info...")
        files = {'image': open(image_path, 'rb')}
        response = requests.post(vision_url, files=files)
        response.raise_for_status()
        
        result = response.json()
        text = result.get('text', [])
        labels = result.get('labels', [])
        web_entities = result.get('web_entities', [])
        
        # Format findings similar to Flutter app
        findings = f"Extracted text: {text}\nLabels: {labels}\nWeb info: {web_entities}"
        
        # Step 2: Send image and findings to VLM for product summary
        print("\nStep 2: Generating product summary with findings...")
        get_product_summary_with_findings(image_path, findings)
        
    except FileNotFoundError:
        print(f"Error: Image file '{image_path}' not found.")
    except requests.exceptions.RequestException as e:
        print(f"Error calling vision backend: {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")


if __name__ == "__main__":
    # Define a default image path directly in the code
    DEFAULT_IMAGE_PATH = "/Users/yousseframy/Documents/Bachelor/lumi_mate_flutter/test_product.jpg"
    
    parser = argparse.ArgumentParser(description='Product Details Client for LumiMate')
    parser.add_argument('--image_path', '-i', default=DEFAULT_IMAGE_PATH,
                        help=f'Path to the image file to be processed (default: {DEFAULT_IMAGE_PATH})')
    parser.add_argument('--findings', '-f', help='Provide findings directly instead of calling vision backend')
    parser.add_argument('--skip_vision', '-s', action='store_true', 
                        help='Skip vision backend and use default placeholder findings')
    args = parser.parse_args()
    
    image_path = args.image_path
    
    # Validate image path
    if not Path(image_path).is_file():
        print(f"Error: Image file '{image_path}' does not exist.")
        print(f"Please ensure the file exists or specify a different path using the --image_path argument")
        exit(1)
        
    print(f"Using image: {image_path}")
    
    # If findings are provided directly or skip_vision is true, use simple approach
    if args.findings:
        get_product_summary_with_findings(image_path, args.findings)
    elif args.skip_vision:
        # Use placeholder findings
        placeholder_findings = "Extracted text: []\nLabels: ['Product', 'Package', 'Container']\nWeb info: []"
        get_product_summary_with_findings(image_path, placeholder_findings)
    else:
        # Use the full two-step process
        analyze_product_and_get_summary(image_path)
