class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  # Pay gem integration
  pay_customer

  # ActiveAgent relationships
  has_many :projects, dependent: :destroy

  def create_default_project!
    projects.create!(
      name: "Default Project",
      environment: "production",
      description: "Default project for #{email}"
    ).tap do |project|
      project.generate_api_token!
    end
  end
end
