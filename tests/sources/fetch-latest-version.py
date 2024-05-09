import requests
from bs4 import BeautifulSoup

def get_latest_python_version():
    url = "https://www.python.org/downloads/"
    response = requests.get(url)
    soup = BeautifulSoup(response.text, 'html.parser')
    version = soup.find('div', {'class': 'download-unknown'}).find('span').text.split(' ')[1]
    print(version)

if __name__ == "__main__":
    get_latest_python_version()
