#!/bin/bash

# Script to help fix project name issues
# The colons and spaces in the project name can cause build issues

echo "Current project name: Runner: Analyzer & Tracking"
echo ""
echo "To fix the dependency file parsing error, consider:"
echo "1. Renaming the project to use underscores or hyphens instead of colons and spaces"
echo "2. For example: 'Runner_Analyzer_Tracking' or 'Runner-Analyzer-Tracking'"
echo ""
echo "Steps to rename:"
echo "1. Close Xcode"
echo "2. Rename the project folder"
echo "3. Rename the .xcodeproj file"
echo "4. Update the project.pbxproj file to reflect the new name"
echo "5. Reopen in Xcode"
echo ""
echo "Alternative: Try building with a different scheme or target name"

