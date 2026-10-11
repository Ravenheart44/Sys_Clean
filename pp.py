import subprocess
import os
import shutil
from tqdm import tqdm

def clean_cache(directories):
    for directory in tqdm(directories, desc="Cleaning Cache", unit="directory"):
        try:
            # Check if the directory exists
            if os.path.exists(directory):
                # Remove all files and subdirectories in the cache directory
                shutil.rmtree(directory)
            else:
                print(f"Directory not found: {directory}")
        except Exception as e:
            print(f"Error cleaning cache for {directory}: {e}")

if __name__ == "__main__":
    # Read cache directory locations from the text file
    filename = 'cache.txt'  # Change the filename as needed
    with open(filename, 'r') as file:
        cache_directories = [line.strip() for line in file.readlines()]

    # Call the function to clean cache directories with a progress bar
    clean_cache(cache_directories)
