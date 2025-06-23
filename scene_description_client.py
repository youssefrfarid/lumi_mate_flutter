#!/usr/bin/env python3
import base64
import json
import requests
import argparse
from pathlib import Path


def send_scene_description_to_api(image_path):
    """
    Python implementation of the sendSceneDescriptionToAPI function from the Flutter app.
    This function sends an image to the API and streams back scene descriptions for visually impaired users.
    
    Args:
        image_path (str): Path to the image file to be processed
        
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
                "content": """You are a helpful assistant for visually impaired users. 
                You will receive images from their point of view. 
                Your task is to describe the scene in a natural, conversational way that helps them understand their surroundings.
                
                Focus on:
                1. Important objects and their relative positions
                2. Potential obstacles or hazards
                3. Notable environmental features
                4. Any text or signs that might be important
                
                Speak directly to the user as if you're their eyes, using phrases like 'In front of you' or 'To your left'.
                
                Keep descriptions concise (ideally 2-3 sentences), focusing only on the most important objects, hazards, and features. Avoid excessive detail or long descriptions unless there is a danger present.
                If you notice any potential dangers, mention them first.""",
            },
            {
                "role": "user",
                "content": [
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
        
        print("Sending image to API for scene description...")
        
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
            
            print("\n\nComplete response:")
            print(complete_response)
            
    except FileNotFoundError:
        print(f"Error: Image file '{image_path}' not found.")
    except requests.exceptions.RequestException as e:
        print(f"Error sending scene description to API: {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")


if __name__ == "__main__":
    # Define a default image path directly in the code
    DEFAULT_IMAGE_PATH = "/Users/yousseframy/Documents/Bachelor/lumi_mate_flutter/test_image.jpg"
    
    parser = argparse.ArgumentParser(description='Scene Description Client for LumiMate')
    parser.add_argument('--image_path', '-i', default=DEFAULT_IMAGE_PATH,
                        help=f'Path to the image file to be processed (default: {DEFAULT_IMAGE_PATH})')
    args = parser.parse_args()
    
    image_path = args.image_path
    
    # Validate image path
    if not Path(image_path).is_file():
        print(f"Error: Image file '{image_path}' does not exist.")
        print(f"Please ensure the file exists or specify a different path using the --image_path argument")
        exit(1)
        
    print(f"Using image: {image_path}")
    send_scene_description_to_api(image_path)
