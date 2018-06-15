# Paparazzi

A simple web service to allow self-service updating of profile pictures in Microsoft Active Directory.  With Paparazzi, a user may self-service update their account's 'thumbnailphoto' attribute. It will ensure the user is uploading a valid JPEG, PNG or GIF, will convert it to a JPEG, and will do its best to resize to 256x256.

This service may be useful to anyone with Microsoft Outlook, Microsoft Lync, Cisco Jabber or other programs that can consume the AD attribute for avatar photos, as there are otherwise relatively few/limited self-service methods for a user to update their picture in LDAP/AD.

## Usage

Paparazzi uses a .env file to load settings to the app. A sample may be found in the file sample.env.

## Built With

* The web layout is based on the ["Stylish Portfolio" theme](https://startbootstrap.com/template-overviews/stylish-portfolio/) from [Start Bootstrap](https://startbootstrap.com/)
* [Bootstrap](http://www.getbootstrap.com/), Copyright (c) 2011-2014 Twitter, Inc. [http://www.getbootstrap.com](http://www.getbootstrap.com/)

## Authors

* Nick Mueller, [CDW](http://www.cdw.com)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
