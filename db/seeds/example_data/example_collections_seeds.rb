# Collections

# Create a collection for the gluconeogenesis study
collection = Collection.new(
  title: 'Gluconeogenesis Study Assets',
  description: 'A collection of all assets related to the gluconeogenesis pathway study in Sulfolobus solfataricus, including data files, models, SOPs, and publications.'
)
collection.contributor = $guest_person
collection.creators = [$admin_person, $guest_person]
collection.projects = [$project]
collection.policy = Policy.create(name: 'default policy', access_type: 1)
collection.license = 'CC-BY-4.0'
collection.annotate_with(['gluconeogenesis', 'collection', 'thermophile'], 'tag', $guest_person)

disable_authorization_checks do
  collection.save!
  collection.annotate_with(['gluconeogenesis', 'collection', 'thermophile'], 'tag', $guest_person)
end

# Add items to the collection
disable_authorization_checks do
  # Add data files
  collection.items.create(asset: $data_file1, comment: 'Validation reference data')
  collection.items.create(asset: $data_file2, comment: 'Combined plot of model and experimental data')

  # Add model
  collection.items.create(asset: $model, comment: 'Mathematical model for the reconstituted enzyme system')

  # Add SOP
  collection.items.create(asset: $sop, comment: 'Protocol for reconstituted enzyme system')

  # Add publication
  collection.items.create(asset: $publication, comment: 'Primary publication for this study')

  # Add presentation
  collection.items.create(asset: $presentation, comment: 'Conference presentation of results')

  puts 'Added items to collection.'
end

puts 'Seeded 1 collection with 6 items.'

# Store reference for other seed files
$collection = collection
