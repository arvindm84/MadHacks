from ultralytics import YOLOWorld
import cv2

# 1. Load a stable model
# 'yolov8s-world.pt' (Small) is fast and usually enough for signs.
# If it misses things, switch to 'yolov8m-world.pt' (Medium).
model = YOLOWorld('yolov8s-world.pt')

# 2. Define Specific Road Sign Classes
# Being specific helps reduce hallucinations.
# Instead of just "sign", we describe the types we see.
# model.set_classes([
#     "traffic sign",           # Generic catch-all
#     "construction sign",      # For the orange ones
#     "stop sign",              # Crucial for safety
#     "no parking sign",        # For the white/red one in your image
#     "speed limit sign",       # Common
#     "traffic light",          # Vehicle signals
#     "pedestrian signal",      # Walk/Don't Walk
#     "traffic cone"            # Keep this, it's useful in the context
# ])
model.set_classes([
    # HEAD-HEIGHT (Things the cane misses - Priority #1)
    "low hanging branch", 
    "protruding sign", 
    "hanging wire", 
    "leaves",
    "green leaves",
    "open casement window",

    # TRIP HAZARDS (Things that are silent/temporary)
    "electric scooter", 
    "sandwich board", 
    "construction cone", 
    "wet floor sign", 
    "garbage can",

    # LIFE SAFETY
    "train platform edge", 
    "open manhole", 
    "crosswalk", 
    "traffic light"
])

# 3. Run Prediction with STABLE settings
# Use the image you just uploaded
image_path = r"C:\Users\Sreevatsa\Documents\GitHub\2D-3D-Modeling\why-are-there-random-electric-scooters-laying-around-v0-z94tv0itheld1.webp" 

results = model.predict(
    image_path,
    # imgsz=640,  # Default 640 is usually fine for signs. 
                  # Increase to 960 or 1280 ONLY if it misses distant signs.
    conf=0.25,    # DO NOT use 0.01 here. 0.25 (25%) stops hallucinations.
    iou=0.45,     # Standard overlap threshold
    rect=True
)

# Keep window open (simple method)
print("Press any key in the terminal to exit...")

annotated_frame = results[0].plot()

# Create a resizable window (good for large images on laptops)
cv2.namedWindow("YOLO Detection", cv2.WINDOW_NORMAL)    
cv2.resizeWindow("YOLO Detection", 1200, 800) # Adjust size to fit your screen

# Show the image
cv2.imshow("YOLO Detection", annotated_frame)

# 5. WAIT INDEFINITELY
print("Press any key on the image window to close it...")
cv2.waitKey(0)  # 0 means "wait forever until a key is pressed"
cv2.destroyAllWindows()
