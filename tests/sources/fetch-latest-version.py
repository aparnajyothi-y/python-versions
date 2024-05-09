import requests
from bs4 import BeautifulSoup
import os

def get_latest_python_version():
    url = "https://www.python.org/downloads/"
    response = requests.get(url)
    soup = BeautifulSoup(response.text, 'html.parser')
    version = soup.find('div', {'class': 'download-unknown'}).find('span').text.split(' ')[1]
    return version

if __name__ == "__main__":
    version = get_latest_python_version()
    print(f"::set-output name=version::{version}")
