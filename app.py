GEMINI_API_KEY = 'AIzaSyDdAQGzJ0nHkfixQn5kGETA-oKKwn9skew'

from google import genai
from PIL import Image

sample_image_path = './media/frames/frame_0001.png'

# Load the image using the Pillow (PIL) library
sample_image = Image.open(sample_image_path)

# The client gets the API key from the environment variable `GEMINI_API_KEY`.
client = genai.Client(api_key=GEMINI_API_KEY)

response = client.models.generate_content(
    model="gemini-2.5-flash", 
    # contents="What is the difference between a partial order relation and other relations"
    contents=[
        sample_image,
        "What is everything you see in this image"
    ]
)
print(response.text)